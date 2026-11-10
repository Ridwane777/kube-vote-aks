# ADR-0005: result over WebSocket, without session affinity

- **Status:** Superseded by [ADR-0009](0009-upstream-components-unmodified.md) (the upstream application must stay unmodified)
- **Date:** 2026-10-15
- **Deciders:** Ridwane777
- **Supersedes:** [ADR-0004](0004-loadbalancer-exposure.md), for the `result` Service configuration only (`sessionAffinity: ClientIP` and `externalTrafficPolicy: Local`). Exposure through 2 `LoadBalancer` Services still stands.

## Context

ADR-0004 kept the original Socket.IO transport (HTTP polling) and compensated with `ClientIP` affinity and a `Local` policy. Zero-downtime update measurements (`curl` loop on the public IP) showed this setup was fragile during result rollouts:

| Test (2026-10-15) | result failures |
|---|---|
| Rollout with a 10 s `preStop` | 1 |
| 2 back-to-back rollouts, 20 s `preStop` | ~3 min outage (58 failures out of 61), not reproduced afterwards |
| 1 rollout, instrumented | 0 out of 70 |
| 2 back-to-back rollouts, instrumented | 1 out of 81 |

Working hypothesis, not proven: affinity pins a client to one pod, which can still receive its traffic while shutting down. The `Local` policy adds a dependency on the Azure Load Balancer health probe.

Separately, result could display negative percentages ("-1 %" with 1, 4, 1 and 0 votes). Each share was rounded and the last one computed by subtraction.

## Options considered

| Option | ✅ | ❌ |
|---|---|---|
| A. Keep polling, tune affinity | Original code untouched | Measured fragility, coarse affinity behind a NAT |
| B. Ingress with cookie affinity | Reliable affinity, single IP | Controller to install, still tied to one pod |
| **C. WebSocket transport only** | One long-lived connection per client: no need for affinity or `Local`, normal load balancing. Socket.IO reconnects automatically to another pod | Modifies the provided code. Clients whose network blocks WebSocket can no longer connect (no polling fallback) |

## Decision

**Option C**, shipped as `result:v2`:

- `views/app.js`: `transports:['websocket']`. The `scores` handler is registered only once, because the server re-sends `message` on every reconnection and each one otherwise added a duplicate handler.
- `views/app.js`: percentages use the largest remainder method. The sum is always 100 and no share is negative (1, 4, 1, 0 → 17, 67, 16, 0).
- `k8s/50-result.yaml`: `sessionAffinity` and `externalTrafficPolicy` removed. A 10 s `preStop` and pod spreading across nodes are kept.

## Verification (2026-10-15, `v2` deployed with `scripts/deploy.sh`)

- WebSocket handshake on the public IP: `101 Switching Protocols`. The Service is `affinity=None`, `policy=Cluster`.
- The 2 result pods are on 2 different nodes.
- `curl` loop during the `v2` deployment, then during 2 back-to-back rollouts: poll 88/88, **result 86/88**. The 2 failures (2 s timeouts, 3 s apart) happened during the back-to-back rollouts. **Zero errors is not yet shown for result**.

## Consequences

### ✅ Gained

- No more affinity: traffic is balanced normally and a pod can disappear without breaking other sessions.
- No more dependency on `externalTrafficPolicy: Local` or the Load Balancer's per-node probe.
- Correct percentages.

### ❌ Lost / risks

- **Provided code modified**: must be justified, and redone whenever a new version of the application is pulled.
- **No polling fallback** for networks that block WebSocket.
- **WebSocket drop on every rollout**: open browsers reconnect (about 1 s), with no visible error.
- **Residual failures during back-to-back rollouts**, cause unknown. Leads: Node.js exits immediately on `SIGTERM` (no graceful shutdown in `server.js`), endpoint propagation delay on AKS.

## Links

- [ADR-0004](0004-loadbalancer-exposure.md)
- Code: `project-applications/poll-application/result/views/app.js`; manifest: `k8s/50-result.yaml`
