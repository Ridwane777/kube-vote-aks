# ADR-0001: Hosting platform — AKS + ACR in Poland Central

- **Status:** Accepted — region and resource group superseded by [ADR-0002](0002-region-spain-central.md)
- **Date:** 2026-10-15
- **Deciders:** Ridwane777

## Context

Project requirements:

- a **multi-node** Kubernetes cluster;
- a **private Docker registry** for the `poll`, `worker` and `result` images;
- anyone must be able to clone the repository and redeploy **onto a ready-to-use cluster on the same platform**.

Own constraints:

- budget: a **100 $ Azure credit**, of which **12.54 € already spent** by the bootstrap VM (measured, Cost Management);
- quotas measured in Poland Central (`az vm list-usage`, 2026-10-14): **6 regional vCPUs** in total, BS family limited to 4 vCPUs, Basv2 / Bsv2 families at 10 vCPUs;
- `Standard_B2s` is **restricted** for this subscription in Poland Central; `Standard_B2als_v2` and `Standard_B2s_v2` are available (`az vm list-skus`);
- the `bernstein-rg` resource group already exists in **Poland Central**.

## Options considered

| Option | Description |
|---|---|
| **A. AKS + ACR** (Azure) | Managed Kubernetes, control plane run by Azure, managed private registry |
| B. k3s on several Azure VMs | Hand-built cluster on 2–3 VMs, self-hosted registry |
| C. Another managed cloud (GKE, EKS, DigitalOcean) | Managed Kubernetes outside Azure |
| D. Minikube on a VM | What the bootstrap used |

### Comparison

| Criterion | A. AKS + ACR | B. k3s on VMs | C. Other cloud | D. Minikube |
|---|---|---|---|---|
| Multi-node (required) | ✅ | ✅ | ✅ | ❌ single node |
| Private registry | ✅ ACR, managed-identity auth | ⚠️ to install and secure yourself | ✅ | ❌ |
| Public IP (`LoadBalancer`) | ✅ native | ⚠️ MetalLB / NodePort to configure | ✅ | ❌ |
| Reproducible by others | ✅ "ready-to-use cluster" | ⚠️ depends on our install | ✅ | ❌ |
| Cost to us | Existing credit | Credit, more VMs | No credit or limited credit | Low |
| Operational load | Low (managed control plane) | High (upgrades, etcd, certificates) | Low | — |

## Decision

**Option A: AKS (Free tier) + ACR (Basic) in `bernstein-rg`, in Poland Central.**

- **Nodes:** 2 × `Standard_B2als_v2` (2 vCPU, 4 GB each), i.e. 4 of the 6 regional vCPUs.
- **Registry:** ACR Basic attached to the cluster with `--attach-acr`: nodes pull images with their managed identity, **no registry secret** in Kubernetes.
- **Region:** Poland Central, where the existing resource group is. Everything in one region = no inter-region transfer fees, data hosted in the EU.
- **Operations:** cluster stopped (`az aks stop`) outside working sessions.

## Consequences

### ✅ Gained

- Requirements covered: multi-node, private registry, external exposure through `LoadBalancer`.
- No control plane to install or maintain (etcd, API server, certificates).
- No registry credentials to manage: ACR access goes through the managed identity.
- 2 nodes make it possible to demonstrate `kubectl drain` and replica spreading.
- 2 vCPUs of quota stay free for a temporary node during an AKS version upgrade (surge).

### ❌ Lost / risks

- **Azure lock-in**: the scripts (`az aks`, `az acr`) are not portable as-is to another cloud. The Kubernetes manifests are.
- **No useful node autoscaling**: 3 nodes at most within the quota (6 vCPUs).
- **No multi-zone high availability**: with 2 nodes, losing one leaves half the capacity.
- **Free tier**: no SLA on the control plane (the Standard tier has one, but it is paid).
- **Recurring cost**: ACR and disks are billed even when the cluster is stopped. There is no budget alert (deliberate choice); the risk of forgetting relies on `az aks stop` discipline.

### Estimated costs

Estimates, to be confirmed with the Azure Pricing Calculator and replaced by amounts measured in Cost Management.

| Item | Cluster running | Cluster stopped |
|---|---|---|
| 2 × `B2als_v2` | ~1.5–2 €/day | 0 € |
| Standard Load Balancer + public IP | ~0.6 €/day | ~0.1 €/day (IP) |
| ACR Basic | ~0.15 €/day | ~0.15 €/day |
| Node OS disks and PVC | ~0.2 €/day | ~0.2 €/day |

## Links

- Supersedes: —
- Superseded by: [ADR-0002](0002-region-spain-central.md) (region and resource group)
