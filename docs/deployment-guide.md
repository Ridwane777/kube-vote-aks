# Guide de déploiement pas à pas

Ce guide va **d'un ordinateur vierge à l'application en ligne**, puis couvre la mise à jour et le retour en arrière. Suivre les étapes dans l'ordre. Chaque étape se termine par une **vérification** : ne pas passer à la suivante tant qu'elle n'est pas bonne.

| # | Étape | Qui | Durée |
|---|---|---|---|
| 1 | [Installer les outils](#étape-1--installer-les-outils) | chaque membre | 10 min |
| 2 | [Récupérer le dépôt](#étape-2--récupérer-le-dépôt) | chaque membre | 1 min |
| 3 | [Se connecter à Azure](#étape-3--se-connecter-à-azure) | chaque membre | 2 min |
| 4 | [Créer le registre et le cluster](#étape-4--créer-le-registre-et-le-cluster-une-seule-fois) | un seul membre, une seule fois | 15 min |
| 5 | [Donner l'accès aux autres membres](#étape-5--donner-laccès-aux-autres-membres) | le membre de l'étape 4 | 2 min |
| 6 | [Se connecter au cluster](#étape-6--se-connecter-au-cluster) | chaque membre | 1 min |
| 7 | [Déployer l'application](#étape-7--déployer-lapplication) | un membre | 5 min |
| 8 | [Vérifier depuis un autre ordinateur](#étape-8--vérifier-depuis-un-autre-ordinateur) | n'importe qui | 2 min |
| 9 | [Mettre à jour sans coupure](#étape-9--mettre-à-jour-sans-coupure) | un membre | 5 min |
| 10 | [Revenir à la version précédente](#étape-10--revenir-à-la-version-précédente-rollback) | un membre | 2 min |
| 11 | [Arrêter, rallumer, supprimer](#étape-11--arrêter-rallumer-supprimer) | un membre | — |
| 12 | [Déployer depuis un lien (GitHub Actions)](#étape-12--déployer-depuis-un-lien-github-actions) | configuration : le propriétaire de l'abonnement, une fois | 5 min |
| 13 | [Déployer depuis un lien (Jenkins)](#étape-13--déployer-depuis-un-lien-jenkins) | configuration : le propriétaire du Jenkins et de l'abonnement, une fois | 15 min |

Les commandes sont pour **Linux (Ubuntu / Debian)**. Pour macOS et Windows, voir les encadrés de l'étape 1.

---

## Étape 1 : Installer les outils

| Outil | Rôle |
|---|---|
| `az` (Azure CLI) | Créer et piloter les ressources Azure |
| `docker` | Construire les images des applications |
| `kubectl` | Piloter le cluster Kubernetes |
| `envsubst` | Remplir le registre et la version dans les manifestes (utilisé par le script) |
| `git`, `openssl`, `curl` | Récupérer le dépôt, générer le mot de passe, tester les pages |

### Linux (Ubuntu / Debian)

```sh
# Outils de base : git, openssl, curl, envsubst (paquet gettext-base)
sudo apt update
sudo apt install -y git openssl curl gettext-base

# Azure CLI (script officiel Microsoft)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Docker (script officiel Docker), puis autoriser votre utilisateur à l'utiliser
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# >>> Fermer la session et se reconnecter (ou redémarrer) pour que ce droit s'applique

# kubectl, installé par l'Azure CLI
sudo az aks install-cli
```

> **macOS** : installer [Docker Desktop](https://www.docker.com/products/docker-desktop/), puis `brew install azure-cli kubectl gettext git`.
>
> **Windows** : utiliser **WSL 2** (Ubuntu) et suivre les commandes Linux ci-dessus dans le terminal Ubuntu. Docker Desktop, avec l'intégration WSL activée, fournit `docker` dans WSL.

### ✅ Vérification

```sh
az version --query '"azure-cli"' -o tsv     # une version, ex. 2.7x
docker run --rm hello-world                 # "Hello from Docker!" (sans sudo)
kubectl version --client                    # Client Version: v1.3x
envsubst --version | head -1                # envsubst (GNU gettext-runtime)
```

Si `docker run` répond `permission denied`, la reconnexion après `usermod` n'a pas été faite.

---

## Étape 2 : Récupérer le dépôt

```sh
git clone git@github.com:Ridwane777/bernstein.git
cd bernstein
```

### ✅ Vérification

```sh
ls       # README.md  docs  k8s  project-applications  scripts
```

**Toutes les commandes suivantes se lancent depuis ce dossier.**

---

## Étape 3 : Se connecter à Azure

```sh
az login
```

Un navigateur s'ouvre. Se connecter avec son compte the school (Azure for Students). Sur une machine sans navigateur : `az login --use-device-code`, puis ouvrir le lien affiché sur un autre appareil.

Si plusieurs abonnements apparaissent, choisir le bon :

```sh
az account list -o table
az account set --subscription "<nom-ou-id-de-l-abonnement>"
```

### ✅ Vérification

```sh
az account show --query "{abonnement:name, compte:user.name}" -o table
```

Le compte et l'abonnement affichés doivent être ceux du groupe. **Vérifier avant de créer quoi que ce soit** : tout ce qui est créé est facturé sur cet abonnement.

---

## Étape 4 : Créer le registre et le cluster (une seule fois)

**Un seul membre** fait cette étape. Les autres passent directement à l'étape 6, une fois l'accès donné (étape 5).

### 4.1 Choisir les noms

```sh
RG=bernstein-spain-rg          # groupe de ressources
LOCATION=spaincentral          # région
ACR_NAME=myregistry      # registre : lettres et chiffres, UNIQUE dans tout Azure
CLUSTER=bernstein-aks          # cluster
```

Si le nom du registre est déjà pris (erreur à l'étape 4.4), en choisir un autre. Il faudra le réutiliser à l'étape 7.

### 4.2 Vérifier ce que l'abonnement autorise

Les abonnements étudiants limitent les régions, les tailles de VM et le nombre de vCPU. Vérifier avant de créer évite les échecs à mi-chemin ([ADR-0002](adr/0002-region-spain-central.md)).

```sh
# Régions autorisées par la politique de l'abonnement
az policy assignment list --query "[].{nom:displayName}" -o table

# Tailles de VM B2 disponibles dans la région (on utilise Standard_B2als_v2)
az vm list-skus -l $LOCATION --size Standard_B2 --query "[?!(restrictions[?type=='Location'])].name" -o tsv

# vCPU utilisés / autorisés dans la région (il en faut 4 de libres)
az vm list-usage -l $LOCATION --query "[?name.value=='cores'].{utilises:currentValue, limite:limit}" -o table
```

✅ `Standard_B2als_v2` apparaît dans la liste, et il reste au moins 4 vCPU libres. Sinon, changer de région (`LOCATION=austriaeast`, par exemple) et recommencer cette étape.

### 4.3 Activer les services Azure

À faire une fois par abonnement (quelques minutes) :

```sh
for p in Microsoft.ContainerRegistry Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.Storage; do
  az provider register --namespace $p --wait
done
```

### 4.4 Créer les ressources

```sh
# Groupe de ressources
az group create -n $RG -l $LOCATION

# Registre d'images privé (≈ 1 min)
az acr create -g $RG -n $ACR_NAME --sku Basic

# Cluster Kubernetes, relié au registre (≈ 10 min)
az aks create -g $RG -n $CLUSTER -l $LOCATION \
  --tier free --node-count 2 --node-vm-size Standard_B2als_v2 \
  --network-plugin azure --network-plugin-mode overlay \
  --attach-acr $ACR_NAME --generate-ssh-keys
```

`--attach-acr` autorise le cluster à télécharger les images du registre, sans mot de passe.

### ✅ Vérification

```sh
az acr show -n $ACR_NAME --query "{nom:name, etat:provisioningState}" -o table           # Succeeded
az aks show -g $RG -n $CLUSTER --query "{etat:provisioningState, power:powerState.code}" -o table   # Succeeded, Running
```

### En cas d'erreur

| Message | Cause | Que faire |
|---|---|---|
| `RequestDisallowedByAzure` | Région interdite par la politique de l'abonnement | Reprendre l'étape 4.2 avec une région autorisée |
| `MissingSubscriptionRegistration` | Service Azure non activé | Refaire l'étape 4.3 |
| `The VM size … is not allowed` ou quota à 0 | Taille de VM indisponible pour AKS dans la région | Changer de région (4.1) |
| `AllocationFailed` | Plus de capacité dans la région à ce moment | `az aks delete -g $RG -n $CLUSTER --yes`, puis réessayer plus tard ou dans une autre région |
| `AlreadyInUse` sur le registre | Nom de registre déjà pris | Changer `ACR_NAME` (4.1) |

---

## Étape 5 : Donner l'accès aux autres membres

Le membre qui a créé l'infrastructure donne le rôle **Contributor** sur le groupe de ressources à chaque autre membre. Ce rôle permet d'accéder au cluster, de l'arrêter et de le rallumer, et de pousser des images dans le registre.

```sh
az role assignment create --assignee <email-the school-du-membre> --role Contributor \
  --scope "$(az group show -n $RG --query id -o tsv)"

# Identifiant de l'abonnement, à transmettre aux autres membres
az account show --query id -o tsv
```

L'autre membre doit pouvoir accéder à cet abonnement. Si `az role assignment create` répond que l'utilisateur est introuvable, l'inviter d'abord depuis le portail Azure (**Microsoft Entra ID → Utilisateurs → Inviter un utilisateur externe**).

### ✅ Vérification

```sh
az role assignment list --scope "$(az group show -n $RG --query id -o tsv)" --query "[].{membre:principalName, role:roleDefinitionName}" -o table
```

---

## Étape 6 : Se connecter au cluster

À faire par **chaque membre**, sur sa propre machine, après les étapes 1 à 3 :

```sh
az account set --subscription <id-de-l-abonnement>    # celui transmis à l'étape 5
az aks get-credentials -g bernstein-spain-rg -n bernstein-aks
```

Cette commande écrit l'accès au cluster dans `~/.kube/config`.

### ✅ Vérification

```sh
kubectl get nodes
```

```
NAME                                STATUS   ROLES    AGE   VERSION
aks-nodepool1-xxxxxxxx-vmss000000   Ready    <none>   …     v1.35.x
aks-nodepool1-xxxxxxxx-vmss000001   Ready    <none>   …     v1.35.x
```

Deux nœuds `Ready`. Si la commande répond `the server could not be reached`, le cluster est peut-être arrêté : voir l'étape 11.

---

## Étape 7 : Déployer l'application

```sh
export ACR_NAME=myregistry                       # le nom choisi à l'étape 4.1
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"     # premier déploiement uniquement
scripts/deploy.sh
```

Le script :

1. construit les 3 images (poll, worker, result) et les pousse dans le registre, avec un tag unique (le hash du commit) ;
2. crée le namespace `bernstein` et le Secret `postgres-secret`, qui contient le mot de passe ;
3. applique les manifestes `k8s/` : PostgreSQL (la table `votes` est créée au premier démarrage), Redis, poll, worker, result ;
4. attend que tout soit prêt et affiche les adresses publiques.

Premier déploiement mesuré : **1 min 45**, plus la durée des builds.

```
==> Public addresses (may take a minute on the first deployment)
poll: http://<ip-poll>
result: http://<ip-result>
```

**Le mot de passe n'est écrit nulle part** : il n'existe que dans le Secret Kubernetes. Pour le relire :
`kubectl get secret postgres-secret -n bernstein -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d`.

### ✅ Vérification

```sh
kubectl get pods -n bernstein
```

Il faut **7 pods `Running` et `1/1`** : `poll` ×2, `result` ×2, `worker`, `redis`, `postgres-0`.

```sh
kubectl get svc -n bernstein            # EXTERNAL-IP de poll et de result
curl -I http://<ip-poll>/               # HTTP/1.1 200 OK
curl -I http://<ip-result>/             # HTTP/1.1 200 OK
```

Si `curl` ne répond pas tout de suite, attendre 1 à 2 minutes : le Load Balancer Azure met un peu de temps à router.

### En cas de problème

| Symptôme | Commande pour voir | Cause fréquente |
|---|---|---|
| `error: docker is not installed` / `envsubst …` | — | Étape 1 incomplète |
| `unauthorized` au `docker push` | `az acr login -n $ACR_NAME` | Pas de droit sur le registre (étape 5) |
| Pod en `ImagePullBackOff` | `kubectl describe pod <pod> -n bernstein` | Cluster non relié au registre : `az aks update -g bernstein-spain-rg -n bernstein-aks --attach-acr $ACR_NAME` |
| Pod en `CrashLoopBackOff` | `kubectl logs <pod> -n bernstein` | Base injoignable ou mot de passe incohérent |
| `CreateContainerConfigError` | `kubectl describe pod <pod> -n bernstein` | Secret manquant : relancer avec `POSTGRES_PASSWORD` défini |
| `EXTERNAL-IP` en `<pending>` | `kubectl get svc -n bernstein -w` | Attendre ; Azure est en train de créer l'IP |

---

## Étape 8 : Vérifier depuis un autre ordinateur

Sur **un autre appareil**, par exemple un téléphone en 4G/5G, hors du réseau de l'ordinateur qui a déployé :

1. Ouvrir `http://<ip-poll>` et voter pour une option.
2. Ouvrir `http://<ip-result>` : le vote apparaît en quelques secondes, **sans recharger la page**.
3. Revoter pour une autre option sur poll : le résultat bascule (un navigateur = un vote, le dernier compte).

### ✅ Vérification côté cluster

```sh
kubectl exec postgres-0 -n bernstein -- psql -U postgres -c 'SELECT vote, count(*) FROM votes GROUP BY vote'
```

---

## Étape 9 : Mettre à jour sans coupure

**Terminal 1** : interroger les deux pages en continu pour compter les erreurs :

```sh
scripts/probe.sh /tmp/probe.log
```

**Terminal 2** : modifier le code d'une application, par exemple un texte dans `project-applications/poll-application/poll/templates/index.html`, puis déployer une nouvelle version :

```sh
export ACR_NAME=myregistry
TAG=v2 scripts/deploy.sh
```

Pendant le déploiement, les pods sont remplacés un par un : un nouveau pod démarre, devient prêt, puis seulement un ancien s'arrête.

```sh
kubectl get pods -n bernstein -w        # pour regarder le remplacement (Ctrl+C pour quitter)
```

Quand le script a fini, faire **Ctrl+C dans le terminal 1** : le résumé indique le nombre de requêtes réussies et en erreur. Les mesures obtenues sont dans [docs/performance](performance/README.md).

### ✅ Vérification

```sh
kubectl get deploy -n bernstein -o custom-columns=APP:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
```

Les images de poll, worker et result portent le nouveau tag (`v2`). Recharger la page : la modification est visible.

---

## Étape 10 : Revenir à la version précédente (rollback)

Chaque déploiement laisse ses images dans le registre. Pour revenir en arrière, redéployer l'ancien tag **sans reconstruire** :

```sh
# Voir les versions disponibles
az acr repository show-tags -n $ACR_NAME --repository poll -o table

# Revenir à la version voulue
TAG=<ancien-tag> SKIP_BUILD=1 scripts/deploy.sh
```

> **Toujours mettre `SKIP_BUILD=1` pour un rollback.** Sans lui, le script reconstruirait l'ancien tag avec le code **actuel**, et l'ancienne version serait perdue.

Alternative immédiate, sans le script, application par application :

```sh
kubectl rollout undo deployment/poll -n bernstein
kubectl rollout status deployment/poll -n bernstein
```

### ✅ Vérification

Même commande qu'à l'étape 9 : les images portent l'ancien tag, et la page affiche l'ancienne version.

---

## Étape 11 : Arrêter, rallumer, supprimer

### Arrêter (à faire après chaque séance : le cluster allumé coûte ≈ 4,3 €/jour)

```sh
az aks stop -g bernstein-spain-rg -n bernstein-aks
```

Les pages ne répondent plus. L'application, le mot de passe et les votes sont conservés. Il reste environ 1 €/jour facturé (IP, registre, disque), voir [docs/costs](costs/README.md).

### Rallumer une application déjà déployée

```sh
az aks start -g bernstein-spain-rg -n bernstein-aks      # quelques minutes
kubectl get pods -n bernstein -w                         # attendre 7 pods Running 1/1, puis Ctrl+C
kubectl get svc -n bernstein                             # mêmes IP qu'avant
curl -I http://<ip-poll>/                                # attendre le 200 (≈ 1 à 2 min après le démarrage)
```

**Inutile de relancer `scripts/deploy.sh`** : Kubernetes redémarre tout seul l'application. Avant une soutenance, rallumer **au moins 10 minutes à l'avance**.

### Supprimer

```sh
kubectl delete namespace bernstein                 # l'application ET les votes (les IP changeront au prochain déploiement)
az group delete -n bernstein-spain-rg --yes        # TOUT : cluster, registre, disques. Plus rien n'est facturé
```

---

## Étape 12 : Déployer depuis un lien (GitHub Actions)

Le workflow [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) lance `scripts/deploy.sh` sur une machine de GitHub. Une fois configuré, on déploie **depuis un navigateur**, sans aucun outil installé :

**https://github.com/Ridwane777/bernstein/actions/workflows/deploy.yml** → **Run workflow**

| Champ | Effet |
|---|---|
| `tag` vide | Construit et déploie le commit actuel de `main` (tag = hash du commit) |
| `tag` + case **rollback** cochée | Redéploie une version existante sans reconstruire |

Le workflow rallume le cluster s'il est arrêté. À la fin, la page du run affiche un tableau avec les adresses de poll et de result.

### 12.1 Configuration (une seule fois, par le propriétaire de l'abonnement)

GitHub s'authentifie auprès d'Azure par **identité fédérée (OIDC)** : aucun mot de passe ni aucune clé n'est stocké, ni dans le dépôt, ni dans GitHub. L'identité n'est acceptée que pour la branche `main` de ce dépôt, et n'a des droits que sur le groupe `bernstein-spain-rg`.

```sh
RG=bernstein-spain-rg
REPO=Ridwane777/bernstein

# 1. Créer l'identité de GitHub dans Azure
APP_ID=$(az ad app create --display-name bernstein-github-deploy --query appId -o tsv)
az ad sp create --id "$APP_ID"

# 2. N'accepter que les runs de la branche main de ce dépôt
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"github-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$REPO:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

# 3. Droits limités au groupe de ressources (cluster, registre)
az role assignment create --assignee "$APP_ID" --role Contributor \
  --scope "$(az group show -n $RG --query id -o tsv)"

# 4. L'identifiant à reporter dans le workflow
echo "$APP_ID"
```

Si l'étape 3 répond que l'identité est introuvable, attendre 30 s et la relancer : Azure met un moment à propager une nouvelle identité.

Reporter ensuite l'identifiant affiché dans [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml), à la ligne `AZURE_CLIENT_ID: REPLACE_WITH_CLIENT_ID`, puis commiter et pousser sur `main`. L'identifiant n'est pas un secret : sans la fédération de l'étape 2, il ne permet rien.

### 12.2 Lancer un déploiement

Depuis le lien ci-dessus (**Run workflow**), ou en ligne de commande :

```sh
gh workflow run deploy.yml                                   # commit actuel
gh workflow run deploy.yml -f tag=<ancien-tag> -f rollback=true   # rollback
gh run watch                                                 # suivre le run
```

### ✅ Vérification

Le run est vert, et son résumé affiche les URL de poll et de result, ainsi que l'image déployée.

| Échec | Cause | Que faire |
|---|---|---|
| `AZURE_CLIENT_ID is not set` | Étape 12.1 non terminée | Reporter l'identifiant dans le workflow |
| `AADSTS70021` / `No matching federated identity` | Run lancé depuis une autre branche que `main` | Lancer depuis `main` |
| `AuthorizationFailed` | Rôle non attribué | Refaire l'étape 3 de 12.1 |

---

## Étape 13 : Déployer depuis un lien (Jenkins)

Alternative à l'étape 12 quand les minutes GitHub Actions de l'organisation sont épuisées ([ADR-0011](adr/0011-deploiement-jenkins.md)). Le [`Jenkinsfile`](../Jenkinsfile) à la racine du dépôt lance le même `scripts/deploy.sh`, sur notre serveur Jenkins.

Lien : **`http://<serveur-jenkins>/job/bernstein-deploy/build`** → **Build with Parameters**

| Paramètre | Effet |
|---|---|
| `TAG` vide | Construit et déploie le commit actuel de `main` |
| `TAG` + `ROLLBACK` coché | Redéploie une version existante sans reconstruire |

### 13.1 Préparer la machine Jenkins (une seule fois)

L'agent Jenkins doit avoir les mêmes outils que l'étape 1, installés pour l'utilisateur qui exécute Jenkins (`jenkins` par défaut) :

```sh
# Sur le VPS, avec les commandes de l'étape 1 : az, docker, kubectl, envsubst, git, openssl
sudo usermod -aG docker jenkins && sudo systemctl restart jenkins

# Vérifier, en tant qu'utilisateur jenkins
sudo -u jenkins bash -c 'az version -o none && docker ps >/dev/null && kubectl version --client && envsubst --version | head -1'
```

### 13.2 Créer l'identité Azure de Jenkins (une seule fois, par le propriétaire de l'abonnement)

Jenkins se connecte à Azure avec un *service principal* : une identité avec mot de passe, dont les droits sont limités au groupe `bernstein-spain-rg`.

```sh
az ad sp create-for-rbac --name bernstein-jenkins-deploy --role Contributor \
  --scopes "$(az group show -n bernstein-spain-rg --query id -o tsv)" \
  --query "{appId:appId, password:password}" -o table
```

**Le mot de passe affiché est un secret.** Le copier **uniquement** dans Jenkins (13.3) : jamais dans le dépôt, dans un fichier ou dans un message. Il n'est affiché qu'une fois. S'il est perdu : `az ad sp credential reset --id <appId>`.

### 13.3 Configurer Jenkins (une seule fois)

1. **Identifiant Azure** : *Manage Jenkins → Credentials → System → Global → Add Credentials*
   - Kind : **Username with password**
   - Username : l'`appId` de 13.2
   - Password : le `password` de 13.2
   - ID : **`azure-deploy-sp`** (le `Jenkinsfile` l'attend sous ce nom)
2. **Accès au dépôt GitHub** (privé) : *Add Credentials* → *Username with password*, avec un compte GitHub membre du dépôt et un **token personnel** (*GitHub → Settings → Developer settings → Personal access tokens*, droit de lecture sur le dépôt), ID `github-bernstein`.
3. **Le job** : *New Item* → nom **`bernstein-deploy`** → **Pipeline** →
   - *Pipeline* → Definition : **Pipeline script from SCM**
   - SCM : Git, URL `https://github.com/Ridwane777/bernstein.git`, credentials `github-bernstein`, branche `*/main`
   - Script Path : `Jenkinsfile`
4. **Lancer une première fois** avec *Build Now*. Jenkins lit le `Jenkinsfile` et découvre les paramètres. Le bouton devient ensuite **Build with Parameters**.

### ✅ Vérification

Le build est vert. En fin de journal : les adresses publiques (`poll: http://…`, `result: http://…`) et l'image déployée.

| Échec dans le journal | Cause | Que faire |
|---|---|---|
| `ERROR: azure-deploy-sp` / credentials introuvables | Identifiant mal nommé | Vérifier l'ID `azure-deploy-sp` (13.3) |
| `az: command not found`, `docker: permission denied` | Outils absents pour l'utilisateur `jenkins` | 13.1 |
| `AADSTS7000215: Invalid client secret` | Mot de passe incorrect ou expiré | `az ad sp credential reset`, puis mettre à jour l'identifiant Jenkins |
| `AuthorizationFailed` | Rôle non attribué | Refaire 13.2 |

**Sécurité :** l'interface Jenkins est exposée sur Internet, et quiconque peut lancer ce job peut déployer et allumer le cluster. Garder Jenkins à jour, désactiver l'inscription libre, et réserver le job aux membres du groupe.

---

## Récapitulatif des commandes

```sh
# Une fois par machine
az login && az aks get-credentials -g bernstein-spain-rg -n bernstein-aks

# Premier déploiement
ACR_NAME=myregistry POSTGRES_PASSWORD="$(openssl rand -hex 24)" scripts/deploy.sh

# Mise à jour / rollback
ACR_NAME=myregistry TAG=v2 scripts/deploy.sh
ACR_NAME=myregistry TAG=<ancien-tag> SKIP_BUILD=1 scripts/deploy.sh

# Fin / début de séance
az aks stop  -g bernstein-spain-rg -n bernstein-aks
az aks start -g bernstein-spain-rg -n bernstein-aks
```
