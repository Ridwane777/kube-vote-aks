# Bernstein : déploiement de l'application Poll sur Kubernetes (AKS)

Ce dépôt contient tout ce qu'il faut pour aller du code source au cluster : construire les images de l'application Poll, les pousser dans un registre privé Azure (ACR), puis les déployer sur Azure Kubernetes Service (AKS). Les pages Poll et Result sont exposées sur Internet.

```
poll ──► redis ──► worker ──► postgres ◄── result
 ▲                                           ▲
 └──── IP publique              IP publique ─┘
```

## 🚀 Déployer en un clic

| Action | Lien |
|---|---|
| **Déployer, arrêter, redémarrer, revenir en arrière** (Jenkins) | **[http://jenkins.example.com:8090/job/bernstein-deploy/build](http://jenkins.example.com:8090/job/bernstein-deploy/build)** → *Build with Parameters* |
| Même chose avec GitHub Actions (quand l'organisation a des minutes) | [Actions → Deploy → Run workflow](https://github.com/Ridwane777/bernstein/actions/workflows/deploy.yml) |

| Paramètre Jenkins | Effet |
|---|---|
| `ACTION` = **deploy**, `TAG` vide | Construit et déploie le dernier commit de `main` (rallume le cluster si besoin) |
| `ACTION` = **deploy**, `TAG` = ancienne version + **ROLLBACK** coché | Revient à cette version sans reconstruire |
| `ACTION` = **stop** / **start** | Arrête / rallume le cluster |

Connexion à Jenkins requise. Configuration : [étape 13 du guide](docs/deployment-guide.md#étape-13--déployer-depuis-un-lien-jenkins). Sans Jenkins, la [procédure en ligne de commande](docs/deployment-guide.md) fait la même chose.

## Contenu

| Chemin | Rôle |
|---|---|
| `project-applications/poll-application/` | Code et Dockerfiles fournis, **non modifiés** (identiques à l'archive d'origine) |
| `k8s/` | Manifestes Kubernetes, appliqués dans l'ordre des numéros |
| `scripts/deploy.sh` | Construction, push vers l'ACR, création du Secret, déploiement, IP publiques |
| `scripts/probe.sh` | Mesure de la disponibilité pendant une mise à jour |
| `scripts/load-test.js` | Test de charge (k6) |
| `Jenkinsfile`, `ci/Dockerfile` | Pipeline Jenkins (déployer, arrêter, redémarrer) et son image d'outils |
| `.github/workflows/deploy.yml` | Même déploiement par GitHub Actions |
| `docs/deployment-guide.md` | **Guide pas à pas**, de l'installation des outils au rollback |
| `docs/adr/` | Décisions d'architecture et leurs compromis |
| `docs/performance/` | Mises à jour sans coupure et test de charge |
| `docs/costs/` | Coûts mesurés et estimés |
| `docs/legal/` | Données personnelles, risques, politique de confidentialité, licences |
| `docs/dependencies.md` | Fournisseurs, images, bibliothèques, secrets |
| `docs/retrospective/` | Ce qu'on garderait, ce qu'on ferait autrement, actions suivantes |
| `docs/business/` | Business plan |
| `docs/kubernetes-guide.md` | Les notions Kubernetes utilisées, expliquées depuis zéro |

## Procédure complète

> **Pour déployer, suivre [docs/deployment-guide.md](docs/deployment-guide.md)** : le guide pas à pas, de l'installation de `az` jusqu'au rollback, avec une vérification à chaque étape. Les sections ci-dessous en sont le résumé.

| Étape | Qui | Section |
|---|---|---|
| 1. Installer les outils | chaque membre | [Prérequis](#prérequis) |
| 2. Créer le registre et le cluster (une seule fois) | un membre | [Créer l'infrastructure Azure](#créer-linfrastructure-azure-une-seule-fois) |
| 3. Donner l'accès aux autres membres | le même membre | [Donner l'accès à un autre membre](#donner-laccès-à-un-autre-membre) |
| 4. Déployer | n'importe quel membre | [Déployer](#déployer) |
| 5. Vérifier depuis un autre ordinateur | n'importe qui | [Vérifier](#vérifier-le-déploiement) |
| 6. Mettre à jour, revenir en arrière | n'importe quel membre | [Mettre à jour](#mettre-à-jour-sans-coupure), [Rollback](#revenir-à-la-version-précédente-rollback) |

## Prérequis

- Un abonnement Azure ;
- en local : `az` (Azure CLI), `docker`, `kubectl`, `envsubst` (paquet `gettext`), `git`, `openssl`.

```sh
az version && docker version && kubectl version --client && envsubst --version | head -1
```

## Créer l'infrastructure Azure (une seule fois)

Notre configuration et ses raisons sont dans l'[ADR-0001](docs/adr/0001-plateforme-aks-acr.md) et l'[ADR-0002](docs/adr/0002-region-spain-central.md). Les noms ci-dessous sont les nôtres. Le nom du registre doit être **unique dans tout Azure** : en choisir un autre pour un nouvel abonnement.

```sh
az login
az account show --query "{abonnement:name, compte:user.name}"   # vérifier le bon compte

RG=bernstein-spain-rg; LOCATION=spaincentral; ACR_NAME=myregistry; CLUSTER=bernstein-aks-2

# 1. Vérifier ce que l'abonnement autorise (régions, tailles de VM, quota)
az policy assignment list --query "[].displayName" -o tsv
az vm list-skus -l $LOCATION --size Standard_B2 --query "[?!(restrictions[?type=='Location'])].name" -o tsv
az vm list-usage -l $LOCATION --query "[?name.value=='cores'].{used:currentValue,limit:limit}" -o table

# 2. Activer les services Azure utilisés (une fois par abonnement)
for p in Microsoft.ContainerRegistry Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.Storage; do
  az provider register --namespace $p --wait
done

# 3. Créer le groupe de ressources, le registre et le cluster (≈ 10 min)
az group create -n $RG -l $LOCATION
az acr create -g $RG -n $ACR_NAME --sku Basic
az aks create -g $RG -n $CLUSTER -l $LOCATION \
  --tier free --node-count 2 --node-vm-size Standard_B2als_v2 \
  --network-plugin azure --network-plugin-mode overlay \
  --attach-acr $ACR_NAME --generate-ssh-keys

# 4. Récupérer l'accès au cluster
az aks get-credentials -g $RG -n $CLUSTER
kubectl get nodes        # 2 nœuds Ready
```

En cas d'échec de `az aks create` :

| Erreur | Cause | Solution |
|---|---|---|
| `RequestDisallowedByAzure` | La région n'est pas autorisée par la politique de l'abonnement | Choisir une région de la liste de l'étape 1 |
| `MissingSubscriptionRegistration` | Service Azure non activé | Refaire l'étape 2 |
| Taille non autorisée, quota à 0 | La taille de VM n'est pas disponible pour AKS dans cette région | Étape 1, choisir une autre région ou une autre taille |
| `AllocationFailed` | Pas de capacité dans la région à ce moment-là | Supprimer le cluster à moitié créé (`az aks delete`) et réessayer plus tard ou ailleurs |

## Donner l'accès à un autre membre

Le membre qui a créé l'infrastructure ajoute l'autre membre comme *Contributor* sur le groupe de ressources. Ce rôle permet de récupérer l'accès au cluster, de l'arrêter et de le rallumer, et de pousser des images dans le registre.

```sh
az role assignment create --assignee <email-du-membre> --role Contributor \
  --scope "$(az group show -n $RG --query id -o tsv)"
```

L'autre membre, sur **sa** machine :

```sh
az login                                   # avec son propre compte
az account set --subscription <id-de-l-abonnement>
az aks get-credentials -g bernstein-spain-rg -n bernstein-aks-2
kubectl get nodes
```

## Ce qui n'est pas dans le dépôt, et où le fournir

| Élément | Où le fournir |
|---|---|
| **Identifiants Azure** | `az login` sur votre machine. Ils restent dans `~/.azure/`, jamais dans le dépôt |
| **Accès au cluster** | `az aks get-credentials` écrit dans `~/.kube/config` |
| **`POSTGRES_PASSWORD`** | Variable d'environnement `POSTGRES_PASSWORD` au **premier** déploiement. Le script crée alors le Secret Kubernetes `postgres-secret` dans le namespace `bernstein`. Ensuite, le Secret existe et la variable n'est plus nécessaire |

## Déployer

```sh
# 1. Se connecter à Azure et au cluster
az login
az aks get-credentials -g <resource-group> -n <cluster>

# 2. Autoriser le cluster à tirer les images du registre (une seule fois)
az aks update -g <resource-group> -n <cluster> --attach-acr <registre>

# 3. Déployer (construction, push, Secret, manifestes)
export ACR_NAME=<registre>                            # nom de l'ACR, sans .azurecr.io
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"    # premier déploiement uniquement
scripts/deploy.sh
```

À la fin, le script affiche les adresses publiques :

```
poll: http://<ip>
result: http://<ip>
```

Chaque déploiement utilise un tag d'image unique : le hash du commit git (avec un suffixe s'il y a des modifications non commitées), ou `TAG=<tag>` pour le choisir.

Pour retrouver les IP plus tard : `kubectl get svc -n bernstein`.

## Vérifier le déploiement

```sh
kubectl get pods -n bernstein          # 7 pods Running 1/1 : 2 poll, 2 result, worker, redis, postgres-0
kubectl get svc -n bernstein           # EXTERNAL-IP de poll et result
curl -I http://<ip-poll>/              # HTTP 200 (peut prendre 1 à 2 minutes au premier déploiement)
```

Puis, **depuis un autre ordinateur** (ou un téléphone sur le réseau mobile) :

1. Ouvrir `http://<ip-poll>` et voter.
2. Ouvrir `http://<ip-result>` : le vote apparaît en quelques secondes, sans recharger la page.
3. Revoter pour une autre option : le résultat bascule (un votant = un vote, le dernier compte).

## Mettre à jour sans coupure

```sh
scripts/probe.sh /tmp/probe.log      # terminal 1 : interroge poll et result en continu
# modifier le code, puis dans le terminal 2 :
TAG=v4 scripts/deploy.sh
# Ctrl+C dans le terminal 1 : nombre de requêtes ok / en erreur
```

Les Deployments font un rolling update (`maxUnavailable: 0`), avec readinessProbe et `preStop`. Les mesures sont dans [docs/performance](docs/performance/README.md).

## Revenir à la version précédente (rollback)

Chaque déploiement laisse ses images dans l'ACR sous son tag. Pour revenir en arrière, redéployer l'ancien tag **sans reconstruire** (`SKIP_BUILD=1`) : reconstruire écraserait l'ancien tag avec le code actuel.

```sh
# Tags disponibles
az acr repository show-tags -n "$ACR_NAME" --repository poll -o table

# Redéployer l'ancien tag (rolling update, sans coupure)
TAG=<ancien-tag> SKIP_BUILD=1 scripts/deploy.sh
```

Alternative immédiate, sans le script : `kubectl rollout undo deployment/<poll|worker|result> -n bernstein`, qui revient à la révision précédente. Le prochain `scripts/deploy.sh` réappliquera le tag qu'on lui donne.

## Mot de passe PostgreSQL

Le mot de passe est fixé au **premier démarrage** de PostgreSQL, sur un disque vide. Modifier le Secret ensuite ne change pas le mot de passe de la base existante. Pour le relire :

```sh
kubectl get secret postgres-secret -n bernstein -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

## Arrêter le cluster

```sh
az aks stop -g <resource-group> -n <cluster>
```

Les nœuds (VM) s'éteignent : les pages ne répondent plus. Sont conservés : les IP publiques, les objets Kubernetes, le Secret et le disque des votes. Les IP, le Load Balancer, l'ACR et le disque restent facturés (≈ 1 €/jour, voir [docs/costs](docs/costs/README.md)).

## Rallumer une application déjà déployée

Pas besoin de relancer `scripts/deploy.sh` : Kubernetes redémarre tout seul les pods à partir des objets conservés.

```sh
# 1. Rallumer le cluster (quelques minutes)
az aks start -g <resource-group> -n <cluster>

# 2. Si kubectl ne trouve pas le cluster (autre machine) : se reconnecter
az aks get-credentials -g <resource-group> -n <cluster>

# 3. Attendre que tous les pods soient Running 1/1 (Ctrl+C pour quitter)
kubectl get pods -n bernstein -w

# 4. Récupérer les adresses publiques (colonne EXTERNAL-IP)
kubectl get svc -n bernstein
```

Les IP restent les mêmes tant que les Services ne sont pas supprimés. **Même quand tous les pods sont `Running`, les pages peuvent ne pas répondre pendant environ 1 à 2 minutes**, le temps que le Load Balancer route vers les nœuds redémarrés (mesuré : ~80 s). Vérifier avec `curl -I http://<ip>/` avant de donner les adresses. Avant une démonstration, rallumer le cluster au moins 10 minutes à l'avance. Le démarrage peut échouer si la région manque de capacité ([ADR-0002](docs/adr/0002-region-spain-central.md)) : réessayer plus tard.

## Tout supprimer

```sh
kubectl delete namespace bernstein   # supprime l'application ET le disque des votes
```
