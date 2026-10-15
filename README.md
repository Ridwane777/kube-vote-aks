# Bernstein : déploiement de l'application Poll sur Kubernetes (AKS)

Ce dépôt contient tout ce qu'il faut pour aller du code source au cluster : construire les images de l'application Poll, les pousser dans un registre privé Azure (ACR), puis les déployer sur Azure Kubernetes Service (AKS). Les pages Poll et Result sont exposées sur Internet.

```
poll ──► redis ──► worker ──► postgres ◄── result
 ▲                                           ▲
 └──── IP publique              IP publique ─┘
```

## Contenu

| Chemin | Rôle |
|---|---|
| `project-applications/poll-application/` | Code et Dockerfiles fournis (result modifié, voir [ADR-0005](docs/adr/0005-result-websocket-sans-affinite.md)) |
| `k8s/` | Manifestes Kubernetes, appliqués dans l'ordre des numéros |
| `scripts/deploy.sh` | Construction, push vers l'ACR, création du Secret, déploiement, IP publiques |
| `scripts/probe.sh` | Mesure de la disponibilité pendant une mise à jour |
| `docs/adr/` | Décisions d'architecture et leurs compromis |
| `docs/performance/` | Mesures de mise à jour sans coupure |
| `docs/kubernetes-guide.md` | Les notions Kubernetes utilisées, expliquées depuis zéro |

## Prérequis

- Un abonnement Azure, avec un cluster **AKS** et un registre **ACR** (voir [ADR-0001](docs/adr/0001-plateforme-aks-acr.md) et [ADR-0002](docs/adr/0002-region-spain-central.md) pour notre configuration) ;
- en local : `az` (Azure CLI), `docker`, `kubectl` et `envsubst` (paquet `gettext`).

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

## Mettre à jour sans coupure

```sh
scripts/probe.sh /tmp/probe.log      # terminal 1 : interroge poll et result en continu
# modifier le code, puis dans le terminal 2 :
TAG=v4 scripts/deploy.sh
# Ctrl+C dans le terminal 1 : nombre de requêtes ok / en erreur
```

Les Deployments font un rolling update (`maxUnavailable: 0`), avec readinessProbe, `preStop` et arrêt propre. Les mesures sont dans [docs/performance](docs/performance/README.md).

## Mot de passe PostgreSQL

Le mot de passe est fixé au **premier démarrage** de PostgreSQL, sur un disque vide. Modifier le Secret ensuite ne change pas le mot de passe de la base existante. Pour le relire :

```sh
kubectl get secret postgres-secret -n bernstein -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

## Arrêter et supprimer

```sh
az aks stop  -g <resource-group> -n <cluster>   # éteint les nœuds (les données sont conservées)
az aks start -g <resource-group> -n <cluster>

kubectl delete namespace bernstein              # supprime l'application ET le disque des votes
```
