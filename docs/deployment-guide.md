# Step-by-step deployment guide

This guide goes **from a blank computer to the application online**, then covers updates and rollback. Follow the steps in order. Each step ends with a **check**: don't move on until it passes.

| # | Step | Who | Time |
|---|---|---|---|
| 1 | [Install the tools](#step-1-install-the-tools) | every operator | 10 min |
| 2 | [Get the repository](#step-2-get-the-repository) | every operator | 1 min |
| 3 | [Log in to Azure](#step-3-log-in-to-azure) | every operator | 2 min |
| 4 | [Create the registry and the cluster](#step-4-create-the-registry-and-the-cluster-once) | the subscription owner, once | 15 min |
| 5 | [Grant access to other operators](#step-5-grant-access-to-other-operators) | the owner from step 4 | 2 min |
| 6 | [Connect to the cluster](#step-6-connect-to-the-cluster) | every operator | 1 min |
| 7 | [Deploy the application](#step-7-deploy-the-application) | an operator | 5 min |
| 8 | [Check from another computer](#step-8-check-from-another-computer) | anyone | 2 min |
| 9 | [Update without downtime](#step-9-update-without-downtime) | an operator | 5 min |
| 10 | [Roll back to the previous version](#step-10-roll-back-to-the-previous-version) | an operator | 2 min |
| 11 | [Stop, start, delete](#step-11-stop-start-delete) | an operator | — |
| 12 | [Deploy from a link (GitHub Actions)](#step-12-deploy-from-a-link-github-actions) | setup: the subscription owner, once | 5 min |
| 13 | [Deploy from a link (Jenkins)](#step-13-deploy-from-a-link-jenkins) | setup: the Jenkins and subscription owner, once | 15 min |

Commands are for **Linux (Ubuntu / Debian)**. For macOS and Windows, see the notes in step 1.

---

## Step 1: Install the tools

| Tool | Role |
|---|---|
| `az` (Azure CLI) | Create and drive Azure resources |
| `docker` | Build the application images |
| `kubectl` | Drive the Kubernetes cluster |
| `envsubst` | Fill in the registry and version in the manifests (used by the script) |
| `git`, `openssl`, `curl` | Get the repository, generate the password, test the pages |

### Linux (Ubuntu / Debian)

```sh
# Base tools: git, openssl, curl, envsubst (gettext-base package)
sudo apt update
sudo apt install -y git openssl curl gettext-base

# Azure CLI (official Microsoft script)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Docker (official Docker script), then allow your user to use it
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# >>> Log out and back in (or reboot) for this right to apply

# kubectl, installed by the Azure CLI
sudo az aks install-cli
```

> **macOS**: install [Docker Desktop](https://www.docker.com/products/docker-desktop/), then `brew install azure-cli kubectl gettext git`.
>
> **Windows**: use **WSL 2** (Ubuntu) and follow the Linux commands above in the Ubuntu terminal. Docker Desktop, with WSL integration enabled, provides `docker` in WSL.

### ✅ Check

```sh
az version --query '"azure-cli"' -o tsv     # a version, e.g. 2.7x
docker run --rm hello-world                 # "Hello from Docker!" (without sudo)
kubectl version --client                    # Client Version: v1.3x
envsubst --version | head -1                # envsubst (GNU gettext-runtime)
```

If `docker run` answers `permission denied`, you did not log back in after `usermod`.

---

## Step 2: Get the repository

```sh
git clone git@github.com:Ridwane777/bernstein.git
cd bernstein
```

Then add the voting application source under `project-applications/poll-application/` (it is not versioned here, see the [README](../README.md#getting-started)).

### ✅ Check

```sh
ls       # README.md  docs  k8s  project-applications  scripts
```

**All following commands are run from this directory.**

---

## Step 3: Log in to Azure

```sh
az login
```

A browser opens. Log in with the account that owns (or has access to) the Azure subscription. On a machine without a browser: `az login --use-device-code`, then open the displayed link on another device.

If several subscriptions show up, pick the right one:

```sh
az account list -o table
az account set --subscription "<subscription-name-or-id>"
```

### ✅ Check

```sh
az account show --query "{subscription:name, account:user.name}" -o table
```

The account and subscription shown must be the intended ones. **Check before creating anything**: everything created is billed to this subscription.

---

## Step 4: Create the registry and the cluster (once)

**Only one person** does this step. Other operators go straight to step 6 once access is granted (step 5).

### 4.1 Choose the names

```sh
RG=bernstein-spain-rg          # resource group
LOCATION=spaincentral          # region
ACR_NAME=myregistry      # registry: letters and digits, UNIQUE across all of Azure
CLUSTER=bernstein-aks-2          # cluster
```

If the registry name is taken (error in step 4.4), choose another. Reuse it in step 7.

### 4.2 Check what the subscription allows

Restricted subscriptions (free credit, corporate) limit regions, VM sizes and vCPU count. Checking before creating avoids half-finished failures ([ADR-0002](adr/0002-region-spain-central.md)).

```sh
# Regions allowed by the subscription policy
az policy assignment list --query "[].{name:displayName}" -o table

# B2 VM sizes available in the region (we use Standard_B2als_v2)
az vm list-skus -l $LOCATION --size Standard_B2 --query "[?!(restrictions[?type=='Location'])].name" -o tsv

# vCPUs used / allowed in the region (4 must be free)
az vm list-usage -l $LOCATION --query "[?name.value=='cores'].{used:currentValue, limit:limit}" -o table
```

✅ `Standard_B2als_v2` is in the list, and at least 4 vCPUs are free. Otherwise change region (`LOCATION=austriaeast`, for example) and redo this step.

### 4.3 Enable the Azure services

Once per subscription (a few minutes):

```sh
for p in Microsoft.ContainerRegistry Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.Storage; do
  az provider register --namespace $p --wait
done
```

### 4.4 Create the resources

```sh
# Resource group
az group create -n $RG -l $LOCATION

# Private image registry (≈ 1 min)
az acr create -g $RG -n $ACR_NAME --sku Basic

# Kubernetes cluster, attached to the registry (≈ 10 min)
az aks create -g $RG -n $CLUSTER -l $LOCATION \
  --tier free --node-count 2 --node-vm-size Standard_B2als_v2 \
  --network-plugin azure --network-plugin-mode overlay \
  --attach-acr $ACR_NAME --generate-ssh-keys
```

`--attach-acr` lets the cluster pull images from the registry, with no password.

### ✅ Check

```sh
az acr show -n $ACR_NAME --query "{name:name, state:provisioningState}" -o table           # Succeeded
az aks show -g $RG -n $CLUSTER --query "{state:provisioningState, power:powerState.code}" -o table   # Succeeded, Running
```

### On error

| Message | Cause | What to do |
|---|---|---|
| `RequestDisallowedByAzure` | Region forbidden by the subscription policy | Redo step 4.2 with an allowed region |
| `MissingSubscriptionRegistration` | Azure service not enabled | Redo step 4.3 |
| `The VM size … is not allowed` or quota at 0 | VM size unavailable for AKS in the region | Change region (4.1) |
| `AllocationFailed` | No capacity left in the region at that moment | `az aks delete -g $RG -n $CLUSTER --yes`, then retry later or in another region |
| `AlreadyInUse` on the registry | Registry name taken | Change `ACR_NAME` (4.1) |

---

## Step 5: Grant access to other operators

The person who created the infrastructure grants the **Contributor** role on the resource group to each other operator. This role allows accessing the cluster, stopping and starting it, and pushing images to the registry.

```sh
az role assignment create --assignee <operator-email> --role Contributor \
  --scope "$(az group show -n $RG --query id -o tsv)"

# Subscription ID, to pass on to the other operators
az account show --query id -o tsv
```

The other operator must have access to this subscription. If `az role assignment create` says the user cannot be found, invite them first from the Azure portal (**Microsoft Entra ID → Users → Invite external user**).

### ✅ Check

```sh
az role assignment list --scope "$(az group show -n $RG --query id -o tsv)" --query "[].{who:principalName, role:roleDefinitionName}" -o table
```

---

## Step 6: Connect to the cluster

Done by **every operator**, on their own machine, after steps 1 to 3:

```sh
az account set --subscription <subscription-id>    # the one passed on in step 5
az aks get-credentials -g bernstein-spain-rg -n bernstein-aks-2
```

This command writes cluster access into `~/.kube/config`.

### ✅ Check

```sh
kubectl get nodes
```

```
NAME                                STATUS   ROLES    AGE   VERSION
aks-nodepool1-xxxxxxxx-vmss000000   Ready    <none>   …     v1.35.x
aks-nodepool1-xxxxxxxx-vmss000001   Ready    <none>   …     v1.35.x
```

Two `Ready` nodes. If the command answers `the server could not be reached`, the cluster may be stopped: see step 11.

---

## Step 7: Deploy the application

```sh
export ACR_NAME=myregistry                       # the name chosen in step 4.1
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"     # first deployment only
scripts/deploy.sh
```

The script:

1. builds the 3 images (poll, worker, result) and pushes them to the registry, with a unique tag (the commit hash);
2. creates the `bernstein` namespace and the `postgres-secret` Secret holding the password;
3. applies the `k8s/` manifests: PostgreSQL (the `votes` table is created on first start), Redis, poll, worker, result;
4. waits for everything to be ready and prints the public addresses.

First deployment measured: **1 min 45**, plus build time.

```
==> Public addresses (may take a minute on the first deployment)
poll: http://<ip-poll>
result: http://<ip-result>
```

**The password is written nowhere**: it only exists in the Kubernetes Secret. To read it back:
`kubectl get secret postgres-secret -n bernstein -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d`.

### ✅ Check

```sh
kubectl get pods -n bernstein
```

You need **7 pods `Running` and `1/1`**: `poll` ×2, `result` ×2, `worker`, `redis`, `postgres-0`.

```sh
kubectl get hpa -n bernstein            # poll and result: MINPODS 2, MAXPODS 4, target 70 %
```

At rest there are 2 poll pods and 2 result pods; under load the HPA adds up to 4 ([ADR-0012](adr/0012-autoscaling-hpa-poll-result.md)). `cpu: <unknown>` during the first minute is normal, until metrics arrive.

> **Cluster deployed before ADR-0012** (Deployments had `replicas: 2`): before the first `scripts/deploy.sh`, remove that field from the `last-applied` annotation, otherwise poll and result drop to 1 pod once:
>
> ```sh
> export REGISTRY=$ACR_NAME.azurecr.io TAG=$(git rev-parse --short HEAD)
> for f in k8s/30-poll.yaml k8s/50-result.yaml; do
>   envsubst '${REGISTRY} ${TAG}' < "$f" | kubectl apply set-last-applied -f -
> done
> ```

```sh
kubectl get svc -n bernstein            # EXTERNAL-IP of poll and result
curl -I http://<ip-poll>/               # HTTP/1.1 200 OK
curl -I http://<ip-result>/             # HTTP/1.1 200 OK
```

If `curl` doesn't answer right away, wait 1 to 2 minutes: the Azure Load Balancer takes a little time to route.

### Troubleshooting

| Symptom | Command to inspect | Common cause |
|---|---|---|
| `error: docker is not installed` / `envsubst …` | — | Step 1 incomplete |
| `unauthorized` on `docker push` | `az acr login -n $ACR_NAME` | No rights on the registry (step 5) |
| Pod in `ImagePullBackOff` | `kubectl describe pod <pod> -n bernstein` | Cluster not attached to the registry: `az aks update -g bernstein-spain-rg -n bernstein-aks-2 --attach-acr $ACR_NAME` |
| Pod in `CrashLoopBackOff` | `kubectl logs <pod> -n bernstein` | Database unreachable or inconsistent password |
| `CreateContainerConfigError` | `kubectl describe pod <pod> -n bernstein` | Missing Secret: rerun with `POSTGRES_PASSWORD` set |
| `EXTERNAL-IP` stuck on `<pending>` | `kubectl get svc -n bernstein -w` | Wait; Azure is creating the IP |

---

## Step 8: Check from another computer

On **another device**, e.g. a phone on 4G/5G, outside the deploying computer's network:

1. Open `http://<ip-poll>` and vote for an option.
2. Open `http://<ip-result>`: the vote appears within seconds, **without reloading the page**.
3. Vote again for another option on poll: the result switches (one browser = one vote, the last one counts).

### ✅ Cluster-side check

```sh
kubectl exec postgres-0 -n bernstein -- psql -U postgres -c 'SELECT vote, count(*) FROM votes GROUP BY vote'
```

---

## Step 9: Update without downtime

**Terminal 1**: poll both pages continuously to count errors:

```sh
scripts/probe.sh /tmp/probe.log
```

**Terminal 2**: change an application's code, e.g. some text in `project-applications/poll-application/poll/templates/index.html`, then deploy a new version:

```sh
export ACR_NAME=myregistry
TAG=v2 scripts/deploy.sh
```

During the deployment pods are replaced one by one: a new pod starts, becomes ready, and only then does an old one stop.

```sh
kubectl get pods -n bernstein -w        # watch the replacement (Ctrl+C to quit)
```

When the script is done, press **Ctrl+C in terminal 1**: the summary shows the number of successful and failed requests. Measured results are in [docs/performance](performance/README.md).

### ✅ Check

```sh
kubectl get deploy -n bernstein -o custom-columns=APP:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
```

The poll, worker and result images carry the new tag (`v2`). Reload the page: the change is visible.

---

## Step 10: Roll back to the previous version

Every deployment leaves its images in the registry. To roll back, redeploy the old tag **without rebuilding**:

```sh
# List available versions
az acr repository show-tags -n $ACR_NAME --repository poll -o table

# Go back to the wanted version
TAG=<old-tag> SKIP_BUILD=1 scripts/deploy.sh
```

> **Always set `SKIP_BUILD=1` for a rollback.** Without it, the script would rebuild the old tag from the **current** code, and the old version would be lost.

Immediate alternative, without the script, one application at a time:

```sh
kubectl rollout undo deployment/poll -n bernstein
kubectl rollout status deployment/poll -n bernstein
```

### ✅ Check

Same command as in step 9: the images carry the old tag, and the page shows the old version.

---

## Step 11: Stop, start, delete

### Stop (after each session: a running cluster costs ≈ 4.3 €/day)

```sh
az aks stop -g bernstein-spain-rg -n bernstein-aks-2
```

Or without a terminal: Jenkins → **Build with Parameters** → `ACTION` = **stop** (step 13). `ACTION` = **start** starts the cluster the same way.

The pages stop answering. The application, the password and the votes are kept. About 1 €/day is still billed (IPs, registry, disk), see [docs/costs](costs/README.md).

### Start an already-deployed application

```sh
az aks start -g bernstein-spain-rg -n bernstein-aks-2      # a few minutes
kubectl get pods -n bernstein -w                         # wait for 7 pods Running 1/1, then Ctrl+C
kubectl get svc -n bernstein                             # same IPs as before
curl -I http://<ip-poll>/                                # wait for the 200 (≈ 1 to 2 min after start)
```

**No need to rerun `scripts/deploy.sh`**: Kubernetes restarts the application by itself. Before a demo, start the cluster **at least 10 minutes ahead**.

### Delete

```sh
kubectl delete namespace bernstein                 # the application AND the votes (IPs will change on the next deployment)
az group delete -n bernstein-spain-rg --yes        # EVERYTHING: cluster, registry, disks. Nothing is billed anymore
```

---

## Step 12: Deploy from a link (GitHub Actions)

The [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) workflow runs `scripts/deploy.sh` on a GitHub runner. Once configured, you deploy **from a browser**, with no tool installed:

**https://github.com/Ridwane777/bernstein/actions/workflows/deploy.yml** → **Run workflow**

| Field | Effect |
|---|---|
| empty `tag` | Builds and deploys the current `main` commit (tag = commit hash) |
| `tag` + **rollback** ticked | Redeploys an existing version without rebuilding |

The workflow starts the cluster if it is stopped. At the end, the run page shows a table with the poll and result addresses.

### 12.1 Setup (once, by the subscription owner)

GitHub authenticates to Azure through **federated identity (OIDC)**: no password or key is stored, neither in the repository nor in GitHub. The identity is only accepted for this repository's `main` branch, and only has rights on the `bernstein-spain-rg` group.

```sh
RG=bernstein-spain-rg
REPO=Ridwane777/bernstein

# 1. Create GitHub's identity in Azure
APP_ID=$(az ad app create --display-name bernstein-github-deploy --query appId -o tsv)
az ad sp create --id "$APP_ID"

# 2. Only accept runs from this repository's main branch
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"github-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$REPO:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

# 3. Rights limited to the resource group (cluster, registry)
az role assignment create --assignee "$APP_ID" --role Contributor \
  --scope "$(az group show -n $RG --query id -o tsv)"

# 4. The ID to put in the workflow
echo "$APP_ID"
```

If step 3 says the identity cannot be found, wait 30 s and rerun it: Azure takes a moment to propagate a new identity.

Then put the printed ID in [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml), on the `AZURE_CLIENT_ID: REPLACE_WITH_CLIENT_ID` line, then commit and push to `main`. The ID is not a secret: without the federation from step 2, it allows nothing.

### 12.2 Run a deployment

From the link above (**Run workflow**), or from the command line:

```sh
gh workflow run deploy.yml                                   # current commit
gh workflow run deploy.yml -f tag=<old-tag> -f rollback=true      # rollback
gh run watch                                                 # follow the run
```

### ✅ Check

The run is green, and its summary shows the poll and result URLs and the deployed image.

| Failure | Cause | What to do |
|---|---|---|
| `AZURE_CLIENT_ID is not set` | Step 12.1 not finished | Put the ID in the workflow |
| `AADSTS70021` / `No matching federated identity` | Run started from a branch other than `main` | Run from `main` |
| `AuthorizationFailed` | Role not assigned | Redo step 3 of 12.1 |

---

## Step 13: Deploy from a link (Jenkins)

Alternative to step 12 when the organisation's GitHub Actions minutes are exhausted ([ADR-0011](adr/0011-jenkins-deployment.md)). The [`Jenkinsfile`](../Jenkinsfile) at the repository root runs the same `scripts/deploy.sh`, on a Jenkins server.

Link: **http://jenkins.example.com:8090/job/bernstein-deploy/build** → **Build with Parameters** (Jenkins login required: anonymous access is disabled)

| Parameters | Effect |
|---|---|
| `ACTION` = **deploy**, empty `TAG` | Starts the cluster if needed, builds and deploys the current `main` commit |
| `ACTION` = **deploy**, `TAG` + `ROLLBACK` ticked | Redeploys an existing version without rebuilding |
| `ACTION` = **stop** | **Stops the cluster** (end of session, ≈ 3.3 €/day saved) |
| `ACTION` = **start** | Starts the cluster without redeploying, and waits for the pages to answer |

### 13.1 Jenkins server prerequisites (checked on the VPS on 2026-10-20)

**Nothing is installed in Jenkins.** Pipeline steps run inside a tools image, [`ci/Dockerfile`](../ci/Dockerfile) (`az`, `kubectl`, `envsubst`, `git`, `openssl`), which Jenkins builds itself on the first build. It only requires that:

| Prerequisite | On the VPS | Check |
|---|---|---|
| *Pipeline*, *Git*, *Credentials Binding*, **Docker Pipeline** plugins | ✅ installed | *Manage Jenkins → Plugins → Installed* |
| Jenkins reaches the host's Docker (socket and binary mounted in its container) | ✅ `jenkins/jenkins:lts` started with `-v /var/run/docker.sock:/var/run/docker.sock -v /usr/bin/docker:/usr/bin/docker` | `docker exec jenkins docker version` |
| The `jenkins` user is in the group owning the socket | ✅ group `988` | `stat -c %g /var/run/docker.sock` on the host. If the result is not `988`, put that number in `--group-add` in the `Jenkinsfile` |
| ≈ 2 GB of disk for the tools image, enough memory for Maven | ✅ 8 vCPU, 23 GB RAM | — |

### 13.2 Create Jenkins's Azure identity (once, by the subscription owner)

Jenkins logs in to Azure with a *service principal*: an identity with a password, whose rights are limited to the `bernstein-spain-rg` group.

```sh
az ad sp create-for-rbac --name bernstein-jenkins-deploy --role Contributor \
  --scopes "$(az group show -n bernstein-spain-rg --query id -o tsv)" \
  --query "{appId:appId, password:password}" -o table
```

**The displayed password is a secret.** Copy it **only** into Jenkins (13.3): never into the repository, a file or a message. It is shown only once. If lost: `az ad sp credential reset --id <appId>`.

### 13.3 Configure Jenkins (once)

1. **Azure credential**: *Manage Jenkins → Credentials → System → Global → Add Credentials*
   - Kind: **Username with password**
   - Username: the `appId` from 13.2
   - Password: the `password` from 13.2
   - ID: **`azure-deploy-sp`** (the `Jenkinsfile` expects this name)
2. **GitHub repository access** (if private): *Add Credentials* → *Username with password*, with a GitHub account that can read the repository and a **personal access token** (*GitHub → Settings → Developer settings → Personal access tokens*, read access to the repository), ID `github-bernstein`.
3. **The job**: *New Item* → name **`bernstein-deploy`** → **Pipeline** →
   - *Pipeline* → Definition: **Pipeline script from SCM**
   - SCM: Git, URL `https://github.com/Ridwane777/bernstein.git`, credentials `github-bernstein`, branch `*/main`
   - Script Path: `Jenkinsfile`
4. **Run it once** with *Build Now*. Jenkins reads the `Jenkinsfile` and discovers the parameters. The button then becomes **Build with Parameters**.

### ✅ Check

Tested on 2026-10-20: build succeeded, `80cb6c5` deployed on poll, worker and result. On the very first build, Jenkins does not know the parameters yet (it discovers them in the `Jenkinsfile`), so they take their default values.

The build is green. At the end of the log: the public addresses (`poll: http://…`, `result: http://…`) and the deployed image.

| Failure in the log | Cause | What to do |
|---|---|---|
| `ERROR: azure-deploy-sp` / credentials not found | Wrongly named credential | Check the `azure-deploy-sp` ID (13.3) |
| `az: command not found`, `docker: permission denied` | Tools missing for the `jenkins` user | 13.1 |
| `AADSTS7000215: Invalid client secret` | Wrong or expired password | `az ad sp credential reset`, then update the Jenkins credential |
| `AuthorizationFailed` | Role not assigned | Redo 13.2 |

**Security:** the Jenkins UI is exposed to the Internet, and anyone who can run this job can deploy and start the cluster. Keep Jenkins up to date, disable self sign-up, and restrict the job to authorised users.

---

## Command summary

```sh
# Once per machine
az login && az aks get-credentials -g bernstein-spain-rg -n bernstein-aks-2

# First deployment
ACR_NAME=myregistry POSTGRES_PASSWORD="$(openssl rand -hex 24)" scripts/deploy.sh

# Update / rollback
ACR_NAME=myregistry TAG=v2 scripts/deploy.sh
ACR_NAME=myregistry TAG=<old-tag> SKIP_BUILD=1 scripts/deploy.sh

# End / start of session
az aks stop  -g bernstein-spain-rg -n bernstein-aks-2
az aks start -g bernstein-spain-rg -n bernstein-aks-2
```
