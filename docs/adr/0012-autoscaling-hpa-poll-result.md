# ADR-0012: Horizontal autoscaling (HPA) of poll and result, from 2 to 4 pods

- **Status:** Accepted, tested on 2026-10-28
- **Date:** 2026-10-28
- **Deciders:** Ridwane777
- **Complements:** [ADR-0008](0008-zero-downtime-updates-and-resources.md), which planned an HPA "once capacity is measured" (see [docs/performance](../performance/README.md))

## Context

poll and result ran with **2 fixed replicas**. The load test (100 virtual users) measured at most **109m of CPU per poll pod**, while its request was 50m. The 2 `B2als_v2` nodes stayed at 16 % CPU: there is room for more pods, but nothing created them automatically.

The HPA computes utilisation **relative to the CPU request**. A request that is too low would make it scale on the slightest load. metrics-server is already installed by AKS.

## Options considered

| Option | ✅ | ❌ |
|---|---|---|
| **A. HPA min 2, max 4, 70 % CPU target** | Keeps high availability (2 pods on 2 nodes, PDB `minAvailable: 1`); fits on the 2 nodes (≈ 0.8 core requested at most out of ≈ 3.8) | Reacts to CPU only |
| B. HPA min 1, max 2 | Fewer pods at rest | A single pod: no redundancy, and the `minAvailable: 1` PDB **blocks node draining** (AKS maintenance) |
| C. Keep 2 fixed replicas | Nothing to do | No reaction to load |
| D. HPA + cluster autoscaler | Can grow beyond 2 nodes | **6 vCPU** quota almost reached; variable cost; useless at this load |
| E. KEDA (scaling on the Redis queue) | Relevant for the worker | One more component to install; the worker stays at 1 replica ([ADR-0007](0007-single-worker-replica.md)) |

## Decision

**Option A**, in `k8s/70-autoscaling.yaml` (`autoscaling/v2`):

- one HPA for poll and one for result: `minReplicas: 2`, `maxReplicas: 4`, `averageUtilization: 70`;
- **scale-down stabilised over 120 s** (`behavior.scaleDown`), to avoid deleting pods (and dropping result's Socket.IO connections) at every dip in load;
- **poll CPU request: 50m → 100m**, close to its measured usage, so that 70 % means real load;
- **`replicas` removed** from the poll and result Deployments: otherwise every `kubectl apply` would reset the pod count to 2, against the HPA's decision;
- no HPA for the worker (single queue consumer, ADR-0007), nor for Redis and PostgreSQL (stateful).

## Consequences

### ✅ Gained

- Measured on 2026-10-28 with `scripts/load-test.js`: poll went from **2 to 3 pods** at 95 % of its request, then back to 2 about 2 minutes after the load ended. result stayed at 2 (30 % at most), as expected given its low usage.
- High availability and PDBs still hold, since the minimum stays 2.
- No extra cost: nodes are billed, not pods.

### ❌ Lost / risks

- **Migrating an existing cluster**: removing `replicas` from a Deployment already created by `kubectl apply` drops it **once to 1 pod** before the HPA scales it back up. Avoided by first clearing the field from the `last-applied` annotation (`kubectl apply set-last-applied`, see the deployment guide). A fresh cluster is not affected.
- **Reaction in about 1 minute** (metrics collected every 15 s, plus pod start): a very short spike passes before the extra pod is ready.
- **result and `ClientIP` affinity**: a new pod only receives new clients. On scale-down, browsers attached to the removed pod reconnect (Socket.IO polling). An audience behind a single NAT stays on one pod, whatever the pod count.
- On the 1st test, right after the cluster was restarted, **18 requests out of 14,343 failed (0.12 %)**, with a p95 of 535 ms. Rerun 20 minutes later: **0 errors out of 16,836, p95 170 ms**, same scale-up to 3 pods. The errors most likely came from the cluster not yet being settled, not from the HPA.

### When to change

- Load beyond 4 poll pods: raise `maxReplicas`, then add a node if node memory exceeds 80 %.
- Growing Redis queue: KEDA on the queue length, provided the worker is made multi-replica.
