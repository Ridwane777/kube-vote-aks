# Comprendre Kubernetes à travers le projet Bernstein

Ce guide explique, sans prérequis, les notions nécessaires pour comprendre et redéployer le projet : ce qu'est Kubernetes, chaque objet utilisé, à quoi il sert et comment les objets s'assemblent. Chaque notion est illustrée par l'application de vote du projet.

---

## 1. Le problème que Kubernetes résout

Une application moderne est faite de plusieurs programmes. Dans ce projet :

| Programme | Langage | Rôle |
|---|---|---|
| **poll** | Python (Flask) | Page web où l'on vote |
| **redis** | — | File d'attente : poll y dépose les votes |
| **worker** | Java | Lit les votes dans Redis et les enregistre dans PostgreSQL |
| **postgres** | — | Base de données qui conserve les votes |
| **result** | Node.js | Page web qui affiche les résultats en temps réel |

```
 Navigateur ──► poll ──► redis ──► worker ──► postgres ◄── result ◄── Navigateur
```

Chaque programme est emballé dans un **conteneur** (une image Docker) : le programme et tout ce dont il a besoin pour tourner.

Lancer 5 conteneurs à la main sur un serveur avec `docker run` fonctionne, mais pose des questions :

- Que se passe-t-il si un conteneur plante ? Il faut le relancer à la main.
- Que se passe-t-il si le serveur tombe en panne ? Tout s'arrête.
- Comment mettre à jour poll sans couper le site ?
- Comment lancer 3 copies de poll quand il y a du monde, et répartir le trafic entre elles ?
- Comment poll trouve-t-il l'adresse de Redis, qui change à chaque redémarrage ?

**Kubernetes** (abrégé **K8s**) est un **orchestrateur** : on lui décrit l'état voulu, par exemple « je veux 2 copies de poll, 1 Redis, 1 PostgreSQL avec un disque ». Il s'occupe en permanence de rendre la réalité conforme à cette description. Il redémarre ce qui plante, déplace les conteneurs quand une machine tombe et fait les mises à jour progressivement.

> **L'idée centrale :** on ne dit pas à Kubernetes *quoi faire* (« lance ce conteneur »), on lui dit *ce qu'on veut* (« il doit y avoir 2 poll »). C'est le modèle **déclaratif**. Une boucle de contrôle compare sans cesse l'état voulu à l'état réel et corrige les écarts.

---

## 2. L'architecture d'un cluster

Un **cluster** est un ensemble de machines gérées ensemble par Kubernetes.

```
┌──────────────────────── Cluster ─────────────────────────┐
│  Control plane (le cerveau)                              │
│   ├─ API server   : la porte d'entrée (kubectl lui parle)│
│   ├─ etcd         : la base qui stocke l'état voulu      │
│   ├─ scheduler    : choisit sur quel nœud placer un pod  │
│   └─ controllers  : boucles qui corrigent les écarts     │
│                                                          │
│  Nœud 1 (VM)                 Nœud 2 (VM)                 │
│   ├─ kubelet                  ├─ kubelet                 │
│   ├─ containerd               ├─ containerd              │
│   └─ pods…                    └─ pods…                   │
└──────────────────────────────────────────────────────────┘
```

| Élément | Rôle |
|---|---|
| **Control plane** | Prend les décisions. Sur AKS, Azure le gère pour nous (et gratuitement en tier Free) |
| **Nœud** (*node*) | Une machine (ici une VM Azure `Standard_B2als_v2`) qui exécute les conteneurs. Le projet en a 2 |
| **kubelet** | Agent sur chaque nœud : reçoit les ordres et lance les conteneurs |
| **containerd** | Le moteur qui exécute réellement les conteneurs (l'équivalent de Docker) |

**kubectl** est l'outil en ligne de commande qui parle à l'API server. Il sait à quel cluster s'adresser grâce au fichier `~/.kube/config` (le *kubeconfig*), rempli par `az aks get-credentials`.

---

## 3. Les manifestes YAML

Chaque objet Kubernetes se décrit dans un fichier **YAML**, appelé un *manifeste*. Ils ont tous la même structure :

```yaml
apiVersion: apps/v1        # version de l'API qui définit ce type d'objet
kind: Deployment           # le type d'objet
metadata:                  # identité de l'objet
  name: poll
  namespace: bernstein
  labels:
    app: poll
spec:                      # l'état voulu, propre à chaque type d'objet
  ...
```

### Rappels de syntaxe YAML

- L'**indentation** (des espaces, jamais de tabulations) définit la hiérarchie.
- `cle: valeur` est un dictionnaire.
- `- element` est un élément de liste.
- `---` sépare plusieurs objets dans le même fichier.

```yaml
env:                  # une liste…
  - name: FOO         # …dont chaque élément est un dictionnaire
    value: "bar"
```

### Commandes de base

```sh
kubectl apply -f fichier.yaml            # crée ou met à jour l'objet décrit
kubectl apply -f k8s/                    # applique tous les fichiers du dossier
kubectl get pods -n bernstein            # liste
kubectl describe pod <nom> -n bernstein  # détail + événements (utile pour déboguer)
kubectl logs <pod> -n bernstein          # sortie du programme
kubectl delete -f fichier.yaml           # supprime
```

Les fichiers YAML du dépôt sont **la source de vérité** : on modifie le fichier puis on fait `apply`, plutôt que de modifier le cluster à la main. Ainsi n'importe qui peut reconstruire le même état depuis le dépôt.

---

## 4. Namespace : ranger et isoler

Un **namespace** est un dossier logique dans le cluster. Les noms y sont uniques : on peut avoir un `poll` dans `bernstein` et un autre dans `test`.

| Namespace | Contenu |
|---|---|
| `default` | Là où vont les objets quand on ne précise rien |
| `kube-system` | Composants internes de Kubernetes (DNS, réseau, stockage…) |
| `kube-public` | Lisible par tous, presque vide |
| `kube-node-lease` | Signaux de vie des nœuds (*heartbeats*) |
| **`bernstein`** | Toute notre application |

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: bernstein
```

**Piège classique :** sans `-n bernstein`, kubectl regarde dans `default` et répond « No resources found ». Pour tout voir : `-A` (tous les namespaces).

---

## 5. Pod : la plus petite unité

Un **pod** est un ou plusieurs conteneurs qui tournent **ensemble sur le même nœud** et partagent la même adresse IP et les mêmes volumes. Dans 99 % des cas, un pod = un conteneur.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels:
    app: hello
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
      env:
        - name: FOO
          value: "bar"
```

Ce qu'il faut retenir :

- **Un pod est éphémère.** S'il meurt, il n'est pas réparé : un autre est créé, avec un **autre nom et une autre IP**.
- On ne crée donc presque **jamais de pod à la main**. On crée un Deployment ou un StatefulSet qui crée et remplace les pods pour nous.
- **Un nœud n'est pas un pod.** Le nœud est la machine, et un nœud héberge de nombreux pods.

Cycle de vie : `Pending` (en attente d'un nœud ou d'une image) → `ContainerCreating` → `Running`. En cas de problème : `CrashLoopBackOff` (le programme plante en boucle), `ImagePullBackOff` (image introuvable ou accès refusé).

---

## 6. Labels et selectors : comment les objets se trouvent

Les objets ne se référencent pas par nom ou par IP, mais par **étiquettes** (*labels*).

```yaml
metadata:
  labels:
    app: poll          # étiquette posée sur le pod
```

```yaml
selector:
  app: poll            # « tous les pods qui ont app=poll »
```

C'est ce mécanisme qui relie un Service à ses pods et un Deployment à ses pods. Si le label et le selector ne correspondent pas exactement (même clé, même valeur), le lien ne se fait pas, sans aucun message d'erreur. Par exemple, un Service affiche alors `Endpoints: <none>`.

---

## 7. Service : une adresse fixe devant des pods qui changent

Les pods changent d'IP à chaque recréation. Un **Service** donne une **adresse stable et un nom DNS** à un groupe de pods sélectionnés par label, et répartit le trafic entre eux.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: bernstein
spec:
  selector:
    app: redis
  ports:
    - port: 6379         # le port du Service (ce que les clients appellent)
      targetPort: 6379   # le port du conteneur (où le trafic arrive)
```

Avec ce Service, poll se connecte simplement à l'hôte **`redis`**, port 6379. Le DNS interne du cluster traduit `redis` en IP du Service, quels que soient les pods derrière. Le nom complet est `redis.bernstein.svc.cluster.local`.

**`port` ou `targetPort` ?** Le client appelle `service:port`, et le Service transmet à `pod:targetPort`. Ils sont souvent identiques, mais on pourrait exposer `port: 80` vers un conteneur qui écoute sur `8080`.

**Endpoints** : la liste des IP de pods actuellement derrière le Service. Elle se vérifie avec `kubectl describe svc <nom>`.

### Les types de Service

| Type | Accessible depuis | Usage dans le projet |
|---|---|---|
| `ClusterIP` (défaut) | L'intérieur du cluster uniquement | redis, et l'accès interne à poll et result |
| *Headless* (`clusterIP: None`) | L'intérieur ; le DNS pointe directement sur chaque pod | postgres (StatefulSet) |
| `NodePort` | Un port ouvert sur chaque nœud | Peu utilisé sur le cloud |
| `LoadBalancer` | Internet : Azure crée un load balancer et une IP publique | Exposition de poll et result (ou d'un Ingress) |

**Affinité de session** (`sessionAffinity: ClientIP`) : envoie toujours le même client vers le même pod. Elle est nécessaire pour **result**, dont la bibliothèque Socket.IO est configurée en mode *polling* : une suite de requêtes HTTP qui doivent arriver au même pod quand il y a plusieurs réplicas.

---

## 8. Deployment et ReplicaSet : faire tourner des applications sans état

Un **Deployment** dit : « je veux N copies de ce pod, avec cette image ». Il est utilisé pour **poll, result, worker et redis**.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: poll
  namespace: bernstein
spec:
  replicas: 2
  selector:
    matchLabels:
      app: poll
  template:                 # le modèle des pods à créer
    metadata:
      labels:
        app: poll           # doit correspondre au selector
    spec:
      containers:
        - name: poll
          image: myregistry.azurecr.io/poll:v1
```

En coulisse :

```
Deployment ──crée──► ReplicaSet (une par version du template) ──crée──► Pods
```

- Le **ReplicaSet** maintient le nombre de pods. Si un pod est supprimé, il en recrée un.
- Chaque modification du `template`, par exemple une nouvelle image, crée un **nouveau ReplicaSet**. Les noms des pods contiennent un hash du template (`poll-7d9f8c6b5-x2kq4`).

### Mise à jour progressive (*rolling update*)

En changeant `poll:v1` en `poll:v2`, le Deployment monte le nouveau ReplicaSet et descend l'ancien **petit à petit**. Il reste toujours des pods en service : **zéro interruption**.

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # au plus 1 pod en plus pendant la mise à jour
      maxUnavailable: 0    # jamais moins de pods prêts que demandé
```

```sh
kubectl rollout status deploy/poll -n bernstein   # suivre la mise à jour
kubectl rollout history deploy/poll -n bernstein  # versions précédentes
kubectl rollout undo deploy/poll -n bernstein     # revenir en arrière
```

**Pourquoi jamais `latest`** : si l'image s'appelle toujours `poll:latest`, le template ne change pas, donc Kubernetes ne fait aucune mise à jour. Avec des tags versionnés (`v1`, `v2`), chaque changement est visible, traçable et réversible.

---

## 9. Sondes (*probes*) : savoir si un pod est vraiment prêt

Un conteneur « Running » n'est pas forcément capable de répondre. Les sondes interrogent l'application :

| Sonde | Question | Si échec |
|---|---|---|
| `readinessProbe` | « Peux-tu recevoir du trafic ? » | Le pod est **retiré du Service** (mais pas tué) |
| `livenessProbe` | « Es-tu encore vivant ? » | Le conteneur est **redémarré** |
| `startupProbe` | « As-tu fini de démarrer ? » | Laisse du temps aux démarrages lents (Java) |

```yaml
readinessProbe:
  httpGet:
    path: /readyz        # poll répond OK seulement s'il joint Redis
    port: 80
  periodSeconds: 5
```

Sans `readinessProbe`, un rolling update enverrait du trafic à des pods pas encore prêts, et le site renverrait des erreurs pendant la mise à jour. Les sondes sont **indispensables pour le zéro downtime**.

---

## 10. Volumes, PV, PVC : garder des données

Le système de fichiers d'un conteneur est **effacé** quand il est recréé. Pour PostgreSQL, il faut un stockage qui survit.

| Objet | Analogie | Rôle |
|---|---|---|
| **PersistentVolume (PV)** | Un disque | Une ressource de stockage réelle (disque Azure, dossier du nœud…) |
| **PersistentVolumeClaim (PVC)** | Un bon de commande | « Il me faut 1 Gi en lecture/écriture ». Kubernetes l'associe (*bind*) à un PV |
| **StorageClass** | Le fournisseur | Crée automatiquement le PV quand un PVC le demande (*provisionnement dynamique*) |

- Au **bootstrap** (Minikube), le PV a été créé **à la main** (`hostPath`, `storageClassName: manual`).
- Sur **AKS**, la StorageClass `default` crée **un vrai disque Azure** automatiquement. On n'écrit que le PVC.

**Modes d'accès** : `ReadWriteOnce` (RWO) = monté par **un seul nœud** à la fois. C'est le cas des disques Azure, et c'est suffisant pour une base de données à une instance.

**Politique de récupération** (*reclaim policy*) : `Delete` (le disque est supprimé avec le PVC, défaut sur AKS) ou `Retain` (le disque est conservé).

---

## 11. StatefulSet : faire tourner une base de données

Un **StatefulSet** ressemble à un Deployment, mais pour les applications **avec état** :

| | Deployment | StatefulSet |
|---|---|---|
| Nom des pods | Aléatoire (`poll-7d9f…-x2k`) | **Stable** et numéroté (`postgres-0`) |
| Stockage | PVC commun, créé à part | **Un PVC par pod**, créé automatiquement |
| Recréation d'un pod | Nouveau nom, aucun disque attaché | **Même nom, même disque** |
| Service | ClusterIP normal | Service *headless* obligatoire (`serviceName`) |

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: bernstein
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:18
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql
  volumeClaimTemplates:        # un PVC sera créé par pod : data-postgres-0
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

Si `postgres-0` est supprimé, il revient sous le même nom et se rattache au PVC `data-postgres-0` : **les votes sont conservés**. Le choix et ses limites sont détaillés dans l'[ADR-0003](adr/0003-manifestes-yaml-postgres-statefulset.md).

---

## 12. ConfigMap et Secret : la configuration hors de l'image

On ne reconstruit pas une image pour changer un paramètre. La configuration est injectée au démarrage.

### ConfigMap : configuration non sensible

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  namespace: bernstein
data:
  schema.sql: |
    CREATE TABLE IF NOT EXISTS votes (...);
```

Un ConfigMap se consomme comme **variables d'environnement** ou comme **fichiers montés** dans le conteneur. Dans le projet, `schema.sql` est monté dans `/docker-entrypoint-initdb.d/`. L'image `postgres` exécute les fichiers de ce dossier **au premier démarrage, sur un disque vide uniquement**.

### Secret : données sensibles

```sh
kubectl create secret generic postgres-secret -n bernstein \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 24)"
```

```yaml
env:
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: POSTGRES_PASSWORD
```

Ce qu'il faut comprendre :

- Dans un Secret, les valeurs sont en **base64**. Ce n'est **pas** du chiffrement : `base64 -d` suffit à les lire. Un fichier Secret YAML commité équivaut donc à un mot de passe en clair dans git.
- C'est pourquoi le Secret est créé **par commande**, hors du dépôt. Le sujet interdit de commiter le mot de passe mais exige de **documenter** comment le créer.
- `kubectl describe secret` affiche la taille des valeurs, pas leur contenu.
- L'accès aux Secrets se restreint avec les droits RBAC du cluster.

---

## 13. Registre d'images : ACR

Les nœuds doivent télécharger (*pull*) les images poll, worker et result. Elles sont stockées dans un **registre privé** : **ACR** (*Azure Container Registry*), `myregistry.azurecr.io`.

```
Machine locale ──docker build──► image ──docker push──► ACR ──pull──► Nœuds AKS
```

Le cluster a été relié au registre avec `--attach-acr` : les nœuds s'authentifient avec leur **identité managée** Azure, sans mot de passe ni Secret de registre dans Kubernetes.

**ACR ne stocke que des images**, pas les données ni les disques. Les disques des PVC sont des *Managed Disks* Azure, dans le resource group technique `MC_bernstein-spain-rg_bernstein-aks-2_spaincentral`.

---

## 14. AKS : Kubernetes géré par Azure

**AKS** (*Azure Kubernetes Service*) fournit un cluster dont Azure gère le control plane. Nous ne gérons que les nœuds et ce qu'on y déploie.

| Commande | Effet |
|---|---|
| `az aks get-credentials -g bernstein-spain-rg -n bernstein-aks-2` | Ajoute le cluster au kubeconfig local |
| `az aks stop -g bernstein-spain-rg -n bernstein-aks-2` | Éteint les nœuds (ne paie plus les VM) |
| `az aks start -g bernstein-spain-rg -n bernstein-aks-2` | Les rallume (les objets et les disques sont conservés) |

Les choix de plateforme et de région sont dans l'[ADR-0001](adr/0001-plateforme-aks-acr.md) et l'[ADR-0002](adr/0002-region-spain-central.md).

---

## 15. Exposer l'application sur Internet

Les Services `ClusterIP` ne sont joignables que depuis l'intérieur du cluster. Pour qu'un navigateur atteigne poll et result :

| Méthode | Principe | Coût et complexité |
|---|---|---|
| Service `LoadBalancer` | Azure crée une IP publique par Service | Simple. Une IP par application |
| **Ingress** + contrôleur (ex. ingress-nginx) | Une seule IP publique ; un routage par nom d'hôte ou par chemin vers les Services | Un composant de plus. Une seule IP, TLS centralisé |

Le choix fera l'objet d'un ADR dédié.

---

## 16. Vue d'ensemble du projet

```
                       Internet
                          │
                 (LoadBalancer / Ingress)
                 ┌────────┴────────┐
                 ▼                 ▼
          Service poll       Service result (affinité de session)
          Deployment ×2      Deployment ×2
                 │                 ▲
                 ▼                 │
          Service redis            │
          Deployment ×1            │
                 │                 │
                 ▼                 │
          Deployment worker        │
                 │                 │
                 ▼                 │
          Service postgres (headless)
          StatefulSet ×1 + PVC (disque Azure)
                 ▲
     Secret postgres-secret   ConfigMap schema.sql

Tout est dans le namespace « bernstein ». Les images viennent de l'ACR.
```

### Ordre de déploiement

| Fichier | Contenu |
|---|---|
| — | `kubectl create secret …` (hors du dépôt) |
| `k8s/00-namespace.yaml` | Namespace `bernstein` |
| `k8s/05-postgres-init.yaml` | ConfigMap `schema.sql` (table `votes`) |
| `k8s/10-postgres.yaml` | Service headless + StatefulSet PostgreSQL |
| `k8s/20-redis.yaml` | Service ClusterIP + Deployment Redis |
| `k8s/30-poll.yaml` | Service `LoadBalancer` + Deployment poll (×2) |
| `k8s/40-worker.yaml` | Deployment worker (×1, pas de Service) |
| `k8s/50-result.yaml` | Service `LoadBalancer` (affinité `ClientIP`) + Deployment result (×2) |
| `k8s/60-disruption-budgets.yaml` | PodDisruptionBudgets : au moins 1 pod poll et 1 pod result pendant un drain de nœud |

---

## 17. Déboguer : la démarche

1. `kubectl get pods -n bernstein` : quel pod n'est pas `Running` ou `READY 1/1` ?
2. `kubectl describe pod <pod> -n bernstein` : lire les **Events** en bas (image introuvable, volume non attaché, sonde en échec…).
3. `kubectl logs <pod> -n bernstein` (ajouter `--previous` après un crash) : l'erreur du programme lui-même.
4. `kubectl describe svc <svc> -n bernstein` : des `Endpoints` vides indiquent un label et un selector qui ne correspondent pas, ou des pods pas prêts.
5. `kubectl get events -n bernstein --sort-by=.lastTimestamp` : la chronologie.

| Symptôme | Cause probable |
|---|---|
| `ImagePullBackOff` | Nom ou tag d'image faux, ACR non relié |
| `CrashLoopBackOff` | Le programme plante : lire les logs (variable manquante, base injoignable) |
| `Pending` | Pas assez de CPU ou de mémoire sur les nœuds, ou PVC non lié |
| `CreateContainerConfigError` | Secret ou ConfigMap référencé inexistant |
| Service sans Endpoints | Label et selector différents, ou readinessProbe en échec |

---

## 18. Glossaire

| Terme | Définition |
|---|---|
| Cluster | Ensemble de nœuds gérés par un control plane |
| Nœud | Machine qui exécute des pods |
| Pod | Un ou plusieurs conteneurs avec la même IP ; éphémère |
| Namespace | Espace de noms qui range et isole les objets |
| Label / selector | Étiquettes et filtres qui relient les objets entre eux |
| Service | Adresse et nom DNS stables devant un groupe de pods |
| Deployment | Maintient N pods identiques sans état ; mises à jour progressives |
| ReplicaSet | Garde le bon nombre de pods pour une version du template |
| StatefulSet | Comme un Deployment, avec une identité et un disque stables par pod |
| PV / PVC / StorageClass | Le disque / la demande de disque / le fournisseur de disques |
| ConfigMap | Configuration non sensible injectée dans les pods |
| Secret | Donnée sensible (encodée en base64, pas chiffrée) |
| Probe | Test de santé : prêt (readiness), vivant (liveness), démarré (startup) |
| Rolling update | Remplacement progressif des pods, sans interruption |
| Ingress | Routage HTTP depuis Internet vers les Services |
| kubectl | Outil en ligne de commande pour piloter le cluster |
| kubeconfig | Fichier `~/.kube/config` : à quel cluster parler, avec quels identifiants |
| AKS / ACR | Kubernetes géré par Azure / registre d'images privé Azure |
