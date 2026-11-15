# Understanding Kubernetes through Kube Vote AKS

This guide explains, with no prerequisites, the concepts needed to understand and redeploy the project: what Kubernetes is, each object used, what it is for and how the objects fit together. Each concept is illustrated with the project's voting application.

---

## 1. The problem Kubernetes solves

A modern application is made of several programs. In this project:

| Program | Language | Role |
|---|---|---|
| **poll** | Python (Flask) | Web page where people vote |
| **redis** | - | Queue: poll drops votes into it |
| **worker** | Java | Reads votes from Redis and stores them in PostgreSQL |
| **postgres** | - | Database that keeps the votes |
| **result** | Node.js | Web page showing results in real time |

```
 Browser ──► poll ──► redis ──► worker ──► postgres ◄── result ◄── Browser
```

Each program is packaged in a **container** (a Docker image): the program and everything it needs to run.

Starting 5 containers by hand on a server with `docker run` works, but raises questions:

- What if a container crashes? It must be restarted by hand.
- What if the server fails? Everything stops.
- How do you update poll without taking the site down?
- How do you run 3 copies of poll under load and spread traffic between them?
- How does poll find Redis's address, which changes on every restart?

**Kubernetes** (**K8s**) is an **orchestrator**: you describe the desired state, e.g. "I want 2 copies of poll, 1 Redis, 1 PostgreSQL with a disk". It continuously makes reality match that description. It restarts what crashes, moves containers when a machine fails and rolls out updates progressively.

> **The core idea:** you don't tell Kubernetes *what to do* ("start this container"), you tell it *what you want* ("there must be 2 poll"). This is the **declarative** model. A control loop constantly compares desired state with actual state and fixes the gaps.

---

## 2. Cluster architecture

A **cluster** is a set of machines managed together by Kubernetes.

```
┌──────────────────────── Cluster ─────────────────────────┐
│  Control plane (the brain)                               │
│   ├─ API server   : the front door (kubectl talks to it) │
│   ├─ etcd         : the store holding the desired state  │
│   ├─ scheduler    : picks the node for each pod          │
│   └─ controllers  : loops that fix the gaps              │
│                                                          │
│  Node 1 (VM)                 Node 2 (VM)                 │
│   ├─ kubelet                  ├─ kubelet                 │
│   ├─ containerd               ├─ containerd              │
│   └─ pods…                    └─ pods…                   │
└──────────────────────────────────────────────────────────┘
```

| Element | Role |
|---|---|
| **Control plane** | Makes the decisions. On AKS, Azure runs it for us (for free on the Free tier) |
| **Node** | A machine (here an Azure `Standard_B2als_v2` VM) that runs containers. The project has 2 |
| **kubelet** | Agent on each node: receives orders and starts containers |
| **containerd** | The engine that actually runs containers (the Docker equivalent) |

**kubectl** is the command-line tool that talks to the API server. It knows which cluster to address from the `~/.kube/config` file (the *kubeconfig*), filled in by `az aks get-credentials`.

---

## 3. YAML manifests

Each Kubernetes object is described in a **YAML** file called a *manifest*. They all share the same structure:

```yaml
apiVersion: apps/v1        # API version that defines this object type
kind: Deployment           # the object type
metadata:                  # the object's identity
  name: poll
  namespace: bernstein
  labels:
    app: poll
spec:                      # the desired state, specific to each object type
  ...
```

### YAML syntax reminders

- **Indentation** (spaces, never tabs) defines the hierarchy.
- `key: value` is a dictionary.
- `- item` is a list item.
- `---` separates several objects in the same file.

```yaml
env:                  # a list…
  - name: FOO         # …whose items are dictionaries
    value: "bar"
```

### Basic commands

```sh
kubectl apply -f file.yaml               # create or update the described object
kubectl apply -f k8s/                    # apply every file in the directory
kubectl get pods -n bernstein            # list
kubectl describe pod <name> -n bernstein # details + events (useful for debugging)
kubectl logs <pod> -n bernstein          # program output
kubectl delete -f file.yaml              # delete
```

The repository's YAML files are **the source of truth**: edit the file then `apply`, rather than changing the cluster by hand. That way anyone can rebuild the same state from the repository.

---

## 4. Namespace: organise and isolate

A **namespace** is a logical folder in the cluster. Names are unique within it: you can have a `poll` in `bernstein` and another in `test`.

| Namespace | Content |
|---|---|
| `default` | Where objects go when nothing is specified |
| `kube-system` | Kubernetes internal components (DNS, network, storage…) |
| `kube-public` | Readable by all, almost empty |
| `kube-node-lease` | Node *heartbeats* |
| **`bernstein`** | Our whole application |

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: bernstein
```

**Classic trap:** without `-n bernstein`, kubectl looks in `default` and answers "No resources found". To see everything: `-A` (all namespaces).

---

## 5. Pod: the smallest unit

A **pod** is one or more containers running **together on the same node**, sharing the same IP address and volumes. In 99 % of cases, one pod = one container.

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

Key points:

- **A pod is ephemeral.** If it dies, it is not repaired: another one is created, with **another name and another IP**.
- So you almost **never create a pod by hand**. You create a Deployment or a StatefulSet that creates and replaces pods for you.
- **A node is not a pod.** The node is the machine, and a node hosts many pods.

Life cycle: `Pending` (waiting for a node or an image) → `ContainerCreating` → `Running`. On trouble: `CrashLoopBackOff` (the program crashes in a loop), `ImagePullBackOff` (image not found or access denied).

---

## 6. Labels and selectors: how objects find each other

Objects don't reference each other by name or IP, but by **labels**.

```yaml
metadata:
  labels:
    app: poll          # label set on the pod
```

```yaml
selector:
  app: poll            # "every pod with app=poll"
```

This mechanism links a Service to its pods and a Deployment to its pods. If label and selector don't match exactly (same key, same value), the link silently fails. A Service then shows `Endpoints: <none>`.

---

## 7. Service: a fixed address in front of changing pods

Pods change IP every time they are recreated. A **Service** gives a **stable address and DNS name** to a group of pods selected by label, and spreads traffic between them.

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
    - port: 6379         # the Service port (what clients call)
      targetPort: 6379   # the container port (where traffic lands)
```

With this Service, poll simply connects to host **`redis`**, port 6379. The cluster's internal DNS resolves `redis` to the Service IP, whatever pods are behind it. The full name is `redis.bernstein.svc.cluster.local`.

**`port` or `targetPort`?** The client calls `service:port`, and the Service forwards to `pod:targetPort`. They are often the same, but you could expose `port: 80` to a container listening on `8080`.

**Endpoints**: the list of pod IPs currently behind the Service. Check it with `kubectl describe svc <name>`.

### Service types

| Type | Reachable from | Use in the project |
|---|---|---|
| `ClusterIP` (default) | Inside the cluster only | redis, and internal access to poll and result |
| *Headless* (`clusterIP: None`) | Inside; DNS points directly at each pod | postgres (StatefulSet) |
| `NodePort` | A port open on every node | Rarely used in the cloud |
| `LoadBalancer` | The Internet: Azure creates a load balancer and a public IP | Exposing poll and result (or an Ingress) |

**Session affinity** (`sessionAffinity: ClientIP`): always sends the same client to the same pod. It is needed for **result**, whose Socket.IO library is configured in *polling* mode: a series of HTTP requests that must reach the same pod when there are several replicas.

---

## 8. Deployment and ReplicaSet: running stateless applications

A **Deployment** says: "I want N copies of this pod, with this image". It is used for **poll, result, worker and redis**.

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
  template:                 # the template of the pods to create
    metadata:
      labels:
        app: poll           # must match the selector
    spec:
      containers:
        - name: poll
          image: myregistry.azurecr.io/poll:v1
```

(In the project's actual manifests, `replicas` is omitted for poll and result because an HPA owns the count, see [ADR-0012](adr/0012-autoscaling-hpa-poll-result.md).)

Behind the scenes:

```
Deployment ──creates──► ReplicaSet (one per template version) ──creates──► Pods
```

- The **ReplicaSet** keeps the pod count. If a pod is deleted, it creates a new one.
- Each change to the `template`, e.g. a new image, creates a **new ReplicaSet**. Pod names contain a hash of the template (`poll-7d9f8c6b5-x2kq4`).

### Rolling update

When `poll:v1` changes to `poll:v2`, the Deployment scales the new ReplicaSet up and the old one down **gradually**. There are always pods serving: **zero interruption**.

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # at most 1 extra pod during the update
      maxUnavailable: 0    # never fewer ready pods than requested
```

```sh
kubectl rollout status deploy/poll -n bernstein   # follow the update
kubectl rollout history deploy/poll -n bernstein  # previous versions
kubectl rollout undo deploy/poll -n bernstein     # roll back
```

**Why never `latest`**: if the image is always `poll:latest`, the template doesn't change, so Kubernetes performs no update. With versioned tags (`v1`, `v2`), every change is visible, traceable and reversible.

---

## 9. Probes: knowing whether a pod is really ready

A "Running" container is not necessarily able to answer. Probes query the application:

| Probe | Question | On failure |
|---|---|---|
| `readinessProbe` | "Can you take traffic?" | The pod is **removed from the Service** (not killed) |
| `livenessProbe` | "Are you still alive?" | The container is **restarted** |
| `startupProbe` | "Have you finished starting?" | Gives slow starters (Java) time |

```yaml
readinessProbe:
  httpGet:
    path: /readyz        # poll answers OK only if it reaches Redis
    port: 80
  periodSeconds: 5
```

Without a `readinessProbe`, a rolling update would send traffic to pods not yet ready, and the site would return errors during the update. Probes are **essential for zero downtime**.

---

## 10. Volumes, PV, PVC: keeping data

A container's filesystem is **wiped** when it is recreated. PostgreSQL needs storage that survives.

| Object | Analogy | Role |
|---|---|---|
| **PersistentVolume (PV)** | A disk | A real storage resource (Azure disk, node directory…) |
| **PersistentVolumeClaim (PVC)** | A purchase order | "I need 1 Gi read/write". Kubernetes *binds* it to a PV |
| **StorageClass** | The supplier | Creates the PV automatically when a PVC asks for it (*dynamic provisioning*) |

- During the **bootstrap** (Minikube), the PV was created **by hand** (`hostPath`, `storageClassName: manual`).
- On **AKS**, the `default` StorageClass creates **a real Azure disk** automatically. Only the PVC is written.

**Access modes**: `ReadWriteOnce` (RWO) = mounted by **a single node** at a time. That is the case for Azure disks, and enough for a single-instance database.

**Reclaim policy**: `Delete` (the disk is deleted with the PVC, AKS default) or `Retain` (the disk is kept).

---

## 11. StatefulSet: running a database

A **StatefulSet** looks like a Deployment, but for **stateful** applications:

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | Random (`poll-7d9f…-x2k`) | **Stable** and numbered (`postgres-0`) |
| Storage | Shared PVC, created separately | **One PVC per pod**, created automatically |
| Pod recreation | New name, no disk attached | **Same name, same disk** |
| Service | Normal ClusterIP | *Headless* Service required (`serviceName`) |

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
  volumeClaimTemplates:        # one PVC per pod: data-postgres-0
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

If `postgres-0` is deleted, it comes back with the same name and reattaches the `data-postgres-0` PVC: **votes are kept**. The choice and its limits are detailed in [ADR-0003](adr/0003-yaml-manifests-postgres-statefulset.md).

---

## 12. ConfigMap and Secret: configuration outside the image

You don't rebuild an image to change a setting. Configuration is injected at start-up.

### ConfigMap: non-sensitive configuration

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

A ConfigMap is consumed as **environment variables** or as **files mounted** in the container. In the project, `schema.sql` is mounted in `/docker-entrypoint-initdb.d/`. The `postgres` image runs the files in that directory **on first start, on an empty disk only**.

### Secret: sensitive data

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

What to understand:

- In a Secret, values are **base64**. That is **not** encryption: `base64 -d` is enough to read them. A committed Secret YAML file is a clear-text password in git.
- That is why the Secret is created **by command**, outside the repository. Requirement: never commit the password, but **document** how to create it.
- `kubectl describe secret` shows the size of the values, not their content.
- Access to Secrets is restricted with the cluster's RBAC rights.

---

## 13. Image registry: ACR

Nodes must *pull* the poll, worker and result images. They are stored in a **private registry**: **ACR** (*Azure Container Registry*), `myregistry.azurecr.io`.

```
Local machine ──docker build──► image ──docker push──► ACR ──pull──► AKS nodes
```

The cluster is attached to the registry with `--attach-acr`: nodes authenticate with their Azure **managed identity**, with no password or registry Secret in Kubernetes.

**ACR only stores images**, not data or disks. PVC disks are Azure *Managed Disks*, in the technical resource group `MC_bernstein-spain-rg_bernstein-aks-2_spaincentral`.

---

## 14. AKS: Kubernetes managed by Azure

**AKS** (*Azure Kubernetes Service*) provides a cluster whose control plane is run by Azure. We only manage the nodes and what we deploy on them.

| Command | Effect |
|---|---|
| `az aks get-credentials -g bernstein-spain-rg -n bernstein-aks-2` | Adds the cluster to the local kubeconfig |
| `az aks stop -g bernstein-spain-rg -n bernstein-aks-2` | Powers the nodes off (VMs no longer billed) |
| `az aks start -g bernstein-spain-rg -n bernstein-aks-2` | Powers them on again (objects and disks are kept) |

Platform and region choices are in [ADR-0001](adr/0001-platform-aks-acr.md) and [ADR-0002](adr/0002-region-spain-central.md).

---

## 15. Exposing the application to the Internet

`ClusterIP` Services are only reachable from inside the cluster. For a browser to reach poll and result:

| Method | Principle | Cost and complexity |
|---|---|---|
| `LoadBalancer` Service | Azure creates one public IP per Service | Simple. One IP per application |
| **Ingress** + controller (e.g. ingress-nginx) | A single public IP; routing by host name or path to the Services | One more component. Single IP, centralised TLS |

The project uses `LoadBalancer` Services, see [ADR-0004](adr/0004-loadbalancer-exposure.md).

---

## 16. Project overview

```
                       Internet
                          │
                 (LoadBalancer / Ingress)
                 ┌────────┴────────┐
                 ▼                 ▼
          Service poll       Service result (session affinity)
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
          StatefulSet ×1 + PVC (Azure disk)
                 ▲
     Secret postgres-secret   ConfigMap schema.sql

Everything is in the "bernstein" namespace. Images come from the ACR.
```

### Deployment order

| File | Content |
|---|---|
| - | `kubectl create secret …` (outside the repository) |
| `k8s/00-namespace.yaml` | `bernstein` namespace |
| `k8s/05-postgres-init.yaml` | `schema.sql` ConfigMap (`votes` table) |
| `k8s/10-postgres.yaml` | Headless Service + PostgreSQL StatefulSet |
| `k8s/20-redis.yaml` | ClusterIP Service + Redis Deployment |
| `k8s/30-poll.yaml` | `LoadBalancer` Service + poll Deployment |
| `k8s/40-worker.yaml` | worker Deployment (×1, no Service) |
| `k8s/50-result.yaml` | `LoadBalancer` Service (`ClientIP` affinity) + result Deployment |
| `k8s/60-disruption-budgets.yaml` | PodDisruptionBudgets: at least 1 poll pod and 1 result pod during a node drain |
| `k8s/70-autoscaling.yaml` | HorizontalPodAutoscalers: poll and result between 2 and 4 pods |

---

## 17. Debugging: the approach

1. `kubectl get pods -n bernstein`: which pod is not `Running` or `READY 1/1`?
2. `kubectl describe pod <pod> -n bernstein`: read the **Events** at the bottom (image not found, volume not attached, failing probe…).
3. `kubectl logs <pod> -n bernstein` (add `--previous` after a crash): the program's own error.
4. `kubectl describe svc <svc> -n bernstein`: empty `Endpoints` means a label/selector mismatch, or pods not ready.
5. `kubectl get events -n bernstein --sort-by=.lastTimestamp`: the timeline.

| Symptom | Likely cause |
|---|---|
| `ImagePullBackOff` | Wrong image name or tag, ACR not attached |
| `CrashLoopBackOff` | The program crashes: read the logs (missing variable, database unreachable) |
| `Pending` | Not enough CPU or memory on the nodes, or PVC not bound |
| `CreateContainerConfigError` | Referenced Secret or ConfigMap does not exist |
| Service without Endpoints | Label and selector differ, or readinessProbe failing |

---

## 18. Glossary

| Term | Definition |
|---|---|
| Cluster | Set of nodes managed by a control plane |
| Node | Machine that runs pods |
| Pod | One or more containers sharing an IP; ephemeral |
| Namespace | Name space that organises and isolates objects |
| Label / selector | Tags and filters that link objects together |
| Service | Stable address and DNS name in front of a group of pods |
| Deployment | Keeps N identical stateless pods; progressive updates |
| ReplicaSet | Keeps the right pod count for one template version |
| StatefulSet | Like a Deployment, with a stable identity and disk per pod |
| PV / PVC / StorageClass | The disk / the disk request / the disk supplier |
| ConfigMap | Non-sensitive configuration injected into pods |
| Secret | Sensitive data (base64-encoded, not encrypted) |
| Probe | Health check: ready (readiness), alive (liveness), started (startup) |
| Rolling update | Progressive pod replacement, without interruption |
| HPA | HorizontalPodAutoscaler: adjusts the pod count to load |
| Ingress | HTTP routing from the Internet to Services |
| kubectl | Command-line tool to drive the cluster |
| kubeconfig | `~/.kube/config` file: which cluster to talk to, with which credentials |
| AKS / ACR | Kubernetes managed by Azure / Azure private image registry |
