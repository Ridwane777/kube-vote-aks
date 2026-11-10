# ADR-0002: Spain Central region and `bernstein-spain-rg` resource group

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** Ridwane777
- **Supersedes:** [ADR-0001](0001-platform-aks-acr.md), for the region and resource group only. The AKS + ACR choice, the Free tier and the 2 `Standard_B2als_v2` nodes still stand.

## Context

ADR-0001 planned AKS and ACR in **Poland Central**, in the `bernstein-rg` resource group. Creation failed several times, for three different reasons:

| Region | Result | Cause (Azure message) |
|---|---|---|
| Poland Central | ❌ ACR rejected | `RequestDisallowedByAzure`: the *Allowed resource deployment regions* subscription policy only allows `swedencentral`, `austriaeast`, `germanywestcentral`, `spaincentral`, `italynorth`. The resource group itself could be created in Poland Central |
| Germany West Central | ❌ AKS rejected | `BadRequest`: no B-series size allowed for AKS; the proposed D/F v6-v7 sizes have a quota of **0 vCPU** |
| Sweden Central | ❌ AKS failed | `AllocationFailed`: not enough `B2als_v2` capacity in the region at creation time |
| Italy North | not tested | No B2 size available (`az vm list-skus`) |
| Austria East | not tested | B2 v2 sizes available, kept in reserve |
| **Spain Central** | ✅ | AKS created successfully |

During these attempts the `bernstein-rg` resource group was deleted from the portal. To avoid waiting for the deletion to finish, a new group was created.

## Options considered

1. **Spain Central**, same `B2als_v2` size.
2. **Austria East**, same size.
3. **Sweden Central** with a larger size (`B2s_v2`, 8 GB): about twice the price per node.
4. Retry Sweden Central later: unknown delay.
5. Request a D/F quota increase in Germany West Central: uncertain answer on this subscription type.

## Decision

**Option 1: everything in Spain Central, in the new `bernstein-spain-rg` resource group.**

- ACR: `myregistry.azurecr.io` (Basic);
- AKS: `bernstein-aks`, Kubernetes 1.35, Free tier, 2 × `Standard_B2als_v2`, attached to the ACR (`--attach-acr`).

## Consequences

### ✅ Gained

- Size and cost planned in ADR-0001 kept.
- ACR and AKS in the same region: no inter-region transfer fees for image pulls.
- EU region, in the subscription's allowed list.
- Austria East remains a fallback, verified on paper.

### ❌ Lost / risks

- **Capacity not guaranteed**: an `az aks start` after a stop can fail for lack of VMs, as in Sweden. The cluster would then stay stopped until capacity returns.
- **Latency** from France slightly higher than from Germany: negligible for this application.
- **The resource group name changes**: all scripts and docs must use `bernstein-spain-rg`.
- **Lesson learned**: check the region policy, the sizes allowed **for AKS** and the regional quota **before** writing the platform ADR. Carried over to the retrospective.

## Links

- [ADR-0001](0001-platform-aks-acr.md)
