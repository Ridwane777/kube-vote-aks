# Kube Vote AKS

**A 3-tier voting application deployed on Azure Kubernetes Service, with one-click deployments, zero-downtime rolling updates, CPU autoscaling and measured results.**

From source code to a public cluster: build the images, push them to a private Azure Container Registry (ACR), deploy them on AKS, expose the Poll and Result pages to the Internet, update and roll back without downtime. Every structuring choice is recorded in an ADR with its trade-offs, and every claim about availability or capacity is backed by a measurement.

```
poll ──► redis ──► worker ──► postgres ◄── result
 ▲                                           ▲
 └──── public IP                public IP ───┘
```

| Component | Stack | Kubernetes object |
|---|---|---|
| poll | Python / Flask (gunicorn) | Deployment + `LoadBalancer` Service, HPA 2–4 pods |
| redis | Redis 8.10.2 | Deployment + ClusterIP Service (queue) |
| worker | Java | Deployment ×1 (no Service) |
| postgres | PostgreSQL 18.6 | StatefulSet + headless Service + 1 Gi Azure disk |
| result | Node.js / Socket.IO | Deployment + `LoadBalancer` Service (`ClientIP` affinity), HPA 2–4 pods |

## What is automated

- **One command** (`scripts/deploy.sh`): build → push to ACR with an immutable tag (git hash) → namespace and Secret → apply `k8s/` → wait for rollouts → print public IPs.
- **One click**: a Jenkins pipeline (`Jenkinsfile`) and a GitHub Actions workflow (`.github/workflows/deploy.yml`, OIDC, no stored secret) that deploy, roll back (`SKIP_BUILD=1`), stop and start the cluster.
- **Zero-downtime rollouts**: `RollingUpdate` with `maxUnavailable: 0`, readiness / liveness / startup probes, `preStop` delays, topology spread, PodDisruptionBudgets.
- **Autoscaling**: HorizontalPodAutoscalers on poll and result (2 to 4 pods, 70 % CPU).
- **No secret in git**: the Postgres password lives only in a Kubernetes Secret; ACR access uses the cluster's managed identity.

### Deploy with one click

| Action | Link |
|---|---|
| **Deploy, stop, start, roll back** (Jenkins) | [http://jenkins.example.com:8090/job/bernstein-deploy/build](http://jenkins.example.com:8090/job/bernstein-deploy/build) → *Build with Parameters* |
| Same with GitHub Actions (when the organisation has minutes) | [Actions → Deploy → Run workflow](https://github.com/Ridwane777/kube-vote-aks/actions/workflows/deploy.yml) |

| Jenkins parameter | Effect |
|---|---|
| `ACTION` = **deploy**, empty `TAG` | Builds and deploys the latest `main` commit (starts the cluster if needed) |
| `ACTION` = **deploy**, `TAG` = old version + **ROLLBACK** ticked | Goes back to that version without rebuilding |
| `ACTION` = **stop** / **start** | Stops / starts the cluster |

Setup: [step 13 of the guide](docs/deployment-guide.md#step-13-deploy-from-a-link-jenkins).

## Measured results

All from [docs/performance](docs/performance/README.md) (k6 and a `curl` probe every 0.2 s, client in France, cluster in Spain Central, 2 × `Standard_B2als_v2`).

| Measure | Result |
|---|---|
| Load test, 100 concurrent users (upstream code, 2026-10-18) | 14,793 requests, **0 errors**, p95 **260 ms** |
| Load test with HPA (2026-10-28, 2nd run) | 16,836 requests (93 req/s), **0 errors**, p95 **170 ms**; poll scaled **2 → 3 → 2** pods |
| Throughput (2026-10-15) | ≈ 28 votes/s, Redis queue always at 0, nodes at 11–16 % CPU |
| Rollout of `v5` | poll 69/69, result 68/68 OK |
| Rollback to `v4` | poll 65/66, result 66/66 OK |
| After `az aks start` | ~80 s before the Load Balancer routes again |

Honest limits: with the upstream result code (Socket.IO polling + `ClientIP` affinity, no graceful shutdown) zero errors is **not guaranteed**: 1 isolated failure per deployment in 2 cases out of 3. Maximum capacity was not reached. Estimated cost: ≈ 4.3 €/day running, ≈ 1 €/day stopped ([docs/costs](docs/costs/README.md)).

## Decision records

| # | Decision | Status |
|---|---|---|
| [0001](docs/adr/0001-platform-aks-acr.md) | Platform: AKS + ACR, 2 `B2als_v2` nodes | Accepted (region superseded by 0002) |
| [0002](docs/adr/0002-region-spain-central.md) | Spain Central region | Accepted |
| [0003](docs/adr/0003-yaml-manifests-postgres-statefulset.md) | Plain YAML, PostgreSQL as a StatefulSet | Accepted |
| [0004](docs/adr/0004-loadbalancer-exposure.md) | 2 `LoadBalancer` Services | Accepted (partly superseded) |
| [0005](docs/adr/0005-result-websocket-without-affinity.md) | result over WebSocket | Superseded by 0009 |
| [0006](docs/adr/0006-ephemeral-redis-without-password.md) | Ephemeral Redis | Accepted |
| [0007](docs/adr/0007-single-worker-replica.md) | Single worker replica | Accepted |
| [0008](docs/adr/0008-zero-downtime-updates-and-resources.md) | Zero-downtime updates, probes, resources | Accepted (partly superseded) |
| [0009](docs/adr/0009-upstream-components-unmodified.md) | Upstream application left unmodified | Accepted |
| [0010](docs/adr/0010-github-actions-deployment.md) | GitHub Actions deployment (OIDC) | Accepted |
| [0011](docs/adr/0011-jenkins-deployment.md) | Jenkins deployment | Accepted, tested |
| [0012](docs/adr/0012-autoscaling-hpa-poll-result.md) | HPA on poll and result, 2–4 pods | Accepted, tested |

Also: [legal analysis](docs/legal/README.md), [costs](docs/costs/README.md), [dependencies](docs/dependencies.md), [business plan](docs/business/README.md), [retrospective](docs/retrospective/README.md), and a [Kubernetes primer](docs/kubernetes-guide.md) built on this project.

## Repository layout

| Path | Role |
|---|---|
| `k8s/` | Kubernetes manifests, applied in numeric order |
| `scripts/deploy.sh` | Build, push to ACR, Secret creation, deployment, public IPs |
| `scripts/probe.sh` | Availability measurement during an update |
| `scripts/load-test.js` | Load test (k6) |
| `Jenkinsfile`, `ci/Dockerfile` | Jenkins pipeline (deploy, stop, start) and its tools image |
| `.github/workflows/deploy.yml` | Same deployment with GitHub Actions |
| `docs/deployment-guide.md` | **Step-by-step guide**, from installing the tools to rollback |
| `docs/` | ADRs, performance, costs, legal, dependencies, business, retrospective |

## Getting started

### 1. Add the application source

The voting application itself is **not versioned here**. It is a variant of Docker's [example-voting-app](https://github.com/dockersamples/example-voting-app), kept unmodified on purpose ([ADR-0009](docs/adr/0009-upstream-components-unmodified.md)). `scripts/deploy.sh` (also called by the `Jenkinsfile` and the GitHub workflow) builds one image per directory, `docker build "$APPS/<service>"` with `APPS=project-applications/poll-application`, so place it like this:

```
project-applications/poll-application/
├── poll/      # Python / Flask, with its Dockerfile (serves /healthz, /readyz)
├── result/    # Node.js / Socket.IO, with its Dockerfile
└── worker/    # Java (Maven), with its Dockerfile; schema.sql (votes table)
```

The `votes` table from `schema.sql` is already embedded in `k8s/05-postgres-init.yaml`; the deployment does not read the file from the source tree. The images must expose port 80 and the `/healthz` and `/readyz` endpoints used by the probes. `project-applications/` is git-ignored.

### 2. Prerequisites

An Azure subscription, and locally `az`, `docker`, `kubectl`, `envsubst` (`gettext` package), `git`, `openssl`.

```sh
az version && docker version && kubectl version --client && envsubst --version | head -1
```

### 3. Create the infrastructure (once)

Rationale in [ADR-0001](docs/adr/0001-platform-aks-acr.md) and [ADR-0002](docs/adr/0002-region-spain-central.md). The registry name must be **unique across Azure**.

```sh
az login
RG=bernstein-spain-rg; LOCATION=spaincentral; ACR_NAME=myregistry; CLUSTER=bernstein-aks-2

# Check what the subscription allows (regions, VM sizes, quota)
az policy assignment list --query "[].displayName" -o tsv
az vm list-skus -l $LOCATION --size Standard_B2 --query "[?!(restrictions[?type=='Location'])].name" -o tsv
az vm list-usage -l $LOCATION --query "[?name.value=='cores'].{used:currentValue,limit:limit}" -o table

# Enable the Azure services used (once per subscription)
for p in Microsoft.ContainerRegistry Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.Storage; do
  az provider register --namespace $p --wait
done

# Resource group, registry and cluster (≈ 10 min)
az group create -n $RG -l $LOCATION
az acr create -g $RG -n $ACR_NAME --sku Basic
az aks create -g $RG -n $CLUSTER -l $LOCATION \
  --tier free --node-count 2 --node-vm-size Standard_B2als_v2 \
  --network-plugin azure --network-plugin-mode overlay \
  --attach-acr $ACR_NAME --generate-ssh-keys

az aks get-credentials -g $RG -n $CLUSTER
kubectl get nodes        # 2 Ready nodes
```

Errors (`RequestDisallowedByAzure`, `AllocationFailed`, …) are covered in the [deployment guide](docs/deployment-guide.md#on-error).

### 4. Deploy

```sh
export ACR_NAME=<registry>                            # ACR name, without .azurecr.io
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"    # first deployment only
scripts/deploy.sh
```

```sh
kubectl get pods -n bernstein          # 7 pods Running 1/1: 2 poll, 2 result, worker, redis, postgres-0
kubectl get svc -n bernstein           # EXTERNAL-IP of poll and result
```

Open `http://<ip-poll>`, vote, then `http://<ip-result>`: the vote shows up within seconds without a reload.

### 5. Update, roll back, stop

```sh
scripts/probe.sh /tmp/probe.log                              # terminal 1: count errors
TAG=v4 scripts/deploy.sh                                     # terminal 2: rolling update
TAG=<old-tag> SKIP_BUILD=1 scripts/deploy.sh                 # rollback, never rebuild an old tag
az aks stop  -g <resource-group> -n <cluster>                # ≈ 1 €/day while stopped
az aks start -g <resource-group> -n <cluster>                # no redeploy needed; wait ~1–2 min for the LB
kubectl delete namespace bernstein                           # remove the app AND the votes disk
```

The PostgreSQL password is fixed on the **first start** on an empty disk; changing the Secret later does not change it. Full procedure, checks and troubleshooting: [docs/deployment-guide.md](docs/deployment-guide.md).

## Author

**Ridwane777**: design, manifests, pipelines, measurements and documentation.
