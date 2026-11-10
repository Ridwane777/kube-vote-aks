# ADR-0008: Zero-downtime updates, probes and resources

- **Status:** Accepted — result part (graceful shutdown, 10 s `preStop`) superseded by [ADR-0009](0009-upstream-components-unmodified.md)
- **Date:** 2026-10-15
- **Deciders:** Ridwane777

## Context

Requirement: an update "*without any downtime*", measured by a client polling the application continuously. The cluster only has 2 small nodes (2 vCPU, 4 GB each). Measurements and incidents are detailed in [docs/performance](../performance/README.md).

## Options considered

| Topic | Options | Choice |
|---|---|---|
| Update strategy | RollingUpdate / Recreate / blue-green (2 Deployments and a Service switch) / canary (Argo Rollouts, Flagger) | **RollingUpdate**, `maxSurge: 1`, `maxUnavailable: 0`: built into Kubernetes, no extra tool |
| Knowing a pod is ready | No probe / readiness only / readiness + liveness + startup | **All three**, on the endpoints provided by the application |
| Stopping old pods | Immediate stop / `preStop` + graceful shutdown | **10 s `preStop`**, plus graceful shutdown of result on `SIGTERM` |
| Resources | None (BestEffort QoS) / `requests` / `requests` + `limits` | **CPU and memory `requests`, memory `limits`** |
| poll server | Image command (1 *sync* gunicorn worker) / overridden command / new Dockerfile | **Command overridden in the manifest** |

## Decision

- **Probes**:
  - `readinessProbe` on `/readyz` (the pod gets traffic only if its dependencies answer);
  - `livenessProbe` on `/healthz` only: a Redis or PostgreSQL outage must not restart every pod in a loop;
  - `startupProbe` for the Java worker;
  - `timeoutSeconds: 2` on poll.
- **`preStop: sleep 10`** on poll and result: the old pod keeps answering while the Load Balancer and kube-proxy stop sending it traffic. Then the pod stops.
- **Resources (requests / memory limit)**:

  | Application | CPU request | Memory request | Memory limit |
  |---|---|---|---|
  | poll | 50m | 64Mi | 128Mi |
  | worker | 100m | 256Mi | 512Mi |
  | result | 50m | 64Mi | 192Mi |

  No CPU limit: it would throttle pods even when the node is idle.
- **poll**: gunicorn started with `--worker-class gthread --workers 2 --threads 4`, instead of the image's single *sync* worker.
- **Spreading**: `topologySpreadConstraints` on `kubernetes.io/hostname`, soft mode (`ScheduleAnyway`) for poll and result.

## Consequences

### ✅ Gained

- Measured during the `v3` deployment with `scripts/deploy.sh`: **0 errors** (poll 65/65, result 65/65).
- poll crash loops after its public exposure are fixed.
- The scheduler places pods according to their `requests`. *Burstable* QoS protects them better than *BestEffort* when a node runs low on memory.

### ❌ Lost / risks

- **One residual failure** on result when a second deployment starts before the first ends (1 attempt out of 3). Cause unknown.
- **Resource values are estimated, not measured** (no `kubectl top` under load). To revisit after a load test.
- **Updates are slower**, because of the 10 s `preStop` per replaced pod.
- **Soft spreading**: under capacity pressure, two replicas can still share a node.
- **poll's command is duplicated** in the manifest: if the Dockerfile changes, the override must follow.
- **No autoscaling (HPA)**: 2 fixed replicas. With 2 small nodes, headroom for load is thin.

### When to change

- **HPA** on poll and result once capacity is measured.
- **PodDisruptionBudget** (`minAvailable: 1`) to protect the applications during AKS node maintenance.
- **Canary** if a bad version must be caught before it serves all traffic.
