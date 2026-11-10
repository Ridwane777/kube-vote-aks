# Costs

Azure subscription with a **100 $ credit**. This document separates what is **measured** (read in Azure) from what is **estimated** (computed, with its method).

## Measured

| Item | Amount | Source |
|---|---|---|
| Bootstrap VM (Minikube), `rg-vm-pl` resource group, deleted | **12.54 €** | Azure portal, Cost Management |
| AKS cluster and ACR (2026-10-15, first day) | **< 0.10 €** | Azure portal, Cost Management, read on 2026-10-16. The portal shows costs several hours late: this amount probably does not cover the whole day yet. To be read again |

The consumption API (`az consumption usage list`) returns no amounts on this subscription (`pretaxCost: None` on all 62 October rows), so amounts are read in the portal.

## Estimated

### Method

- **Prices**: [Azure Retail Prices API](https://prices.azure.com/api/retail/prices), in EUR, `spaincentral` region, pay-as-you-go, read on 2026-10-15.
- **Quantities**: actual cluster resources, read with `az` on 2026-10-15:
  - 2 `Standard_B2als_v2` nodes;
  - a 128 GB **Premium SSD** (P10) OS disk per node, the AKS default;
  - 1 PVC disk of 1 GB, Standard SSD (E1);
  - 3 Standard public IPs: cluster egress, poll and result;
  - 1 Standard Load Balancer with 2 rules + 1 outbound rule;
  - an ACR Basic holding 0.26 GB of images.
- **Conversion**: 1 month = 30.4 days. The AKS control plane is free on the Free tier.

### Cluster running

| Item | Computation | €/day |
|---|---|---|
| 2 `B2als_v2` VMs | 2 × 0.043 €/h × 24 | 2.06 |
| 2 P10 OS disks (128 GB Premium) | 2 × 19.08 €/month | 1.26 |
| Standard Load Balancer (≤ 5 rules) | 0.022 €/h × 24 | 0.53 |
| 3 Standard public IPs | 3 × 0.0044 €/h × 24 | 0.32 |
| ACR Basic (10 GB included) | 0.1466 €/day | 0.15 |
| E1 PVC disk (1 GB) | 0.264 €/month | 0.01 |
| **Total** | | **≈ 4.3 €/day (≈ 131 €/month)** |

### Cluster stopped (`az aks stop`)

VMs are no longer billed. Node OS disks are deleted with the instances: to be confirmed in the portal after a stop. Public IPs, the Load Balancer, the ACR and the PVC disk are still billed.

| Item | €/day |
|---|---|
| Public IPs + Load Balancer + ACR + PVC | **≈ 1.0** |

### Gap with ADR-0001

[ADR-0001](../adr/0001-platform-aks-acr.md) estimated 2.5 to 3 €/day, with 0.2 €/day of disks. It missed that the AKS default OS disk is a **128 GB Premium SSD**, which alone costs 1.26 €/day, i.e. **30 % of the total**. The ADR is not rewritten: the gap is corrected here and carried over to the retrospective.

## What it means for the credit

With a 100 $ credit (≈ 92 €), minus the 12.54 € already spent:

| Usage | Remaining credit lasts (≈ 80 €) |
|---|---|
| Cluster always on | ≈ 18 days |
| On 4 h per working day, stopped otherwise | ≈ 1.0 + 4/24 × 3.3 ≈ 1.6 €/day → ≈ 50 days |

## Possible savings

| Action | Estimated saving | Trade-off |
|---|---|---|
| Stop the cluster outside working sessions (`az aks stop`) | ≈ 3.3 € per stopped day | Start takes a few minutes, capacity not guaranteed (ADR-0002) |
| 30 GB OS disk (P4, 5.11 €/month) instead of 128 GB (`--node-osdisk-size 30` on a new node pool) | ≈ 0.92 €/day | Recreate the node pool. 30 GB is enough for the images used (0.26 GB) |
| Standard SSD OS disk | Even more | Slower pod start |
| A single public IP with an Ingress | ≈ 0.1 €/day | See [ADR-0004](../adr/0004-loadbalancer-exposure.md) |
| Delete everything (`az group delete`) between project phases | Everything | Recreate everything (≈ 10 min with the README) |
