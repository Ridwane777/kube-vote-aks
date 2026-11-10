# Performance: zero-downtime updates and load testing

Requirement: an update must be deployed "*without any downtime*", i.e. a client polling the application continuously must get no error. This document describes the measurement method, the problems found, the fixes and the results, **failures included**.

## Method

| Item | Value |
|---|---|
| Cluster | AKS `bernstein-aks`, Kubernetes 1.35.8, 2 `Standard_B2als_v2` nodes (2 vCPU, 4 GB), Spain Central |
| Client | One machine (in France), through the public IPs of the `LoadBalancer` Services |
| Tool | [`scripts/probe.sh`](../../scripts/probe.sh): a `curl` on `/` of poll then result, every 0.2 s, 2 s timeout |
| Criterion | Any response other than HTTP 200 is an error (`000` = no response within 2 s) |
| Date | 2026-10-15 |

Log format: `time service code` (e.g. `22:52:09.344 result 000`).

### Reproduce

```sh
scripts/probe.sh /tmp/probe.log                          # terminal 1
ACR_NAME=<registry> TAG=<new-tag> scripts/deploy.sh      # terminal 2
# Ctrl+C in terminal 1: ok / error summary
```

Harder scenario, used to stress the fixes: 2 back-to-back result rollouts (`kubectl rollout restart deploy/result -n bernstein` twice, waiting for each to finish).

## Problems found and fixes

| # | Measured symptom | Cause | Fix |
|---|---|---|---|
| 1 | As soon as it is exposed publicly, poll restarts in a loop (6-7 restarts, `CrashLoopBackOff`), CSS not loaded, error page | The image runs gunicorn with **a single *sync* worker**. An idle connection (browser preconnect, bot) blocks it, the `livenessProbe` exceeds 1 s and Kubernetes kills the container | Overridden `command`: `--worker-class gthread --workers 2 --threads 4`. `timeoutSeconds: 2` on the probes. Verified: with 3 idle connections open, `/healthz` still answers |
| 2 | 1 poll failure during a rolling update | The old pod stops before the Load Balancer and kube-proxy have removed it from their lists | 10 s `preStop`: the pod keeps answering during propagation |
| 3 | result failures during rollouts, once a ~3 min outage (58 out of 61) | Hypothesis: `ClientIP` affinity + `externalTrafficPolicy: Local`, needed by Socket.IO's polling transport | Switch to WebSocket transport, affinity removed ([ADR-0005](../adr/0005-result-websocket-without-affinity.md)) |
| 4 | Still 2 failures out of 88 during 2 back-to-back rollouts | Node.js exited abruptly on `SIGTERM` | Graceful shutdown in `server.js`: finish in-flight requests, close WebSockets and PostgreSQL |
| — | Both replicas of an application sometimes on the same node | The scheduler does not guarantee spreading | `topologySpreadConstraints` (soft, `ScheduleAnyway`) |

Fixes 3 and 4 were later reverted to keep the upstream code unmodified ([ADR-0009](../adr/0009-upstream-components-unmodified.md)).

## Results

### Before fixes 3 and 4

| Test | poll | result |
|---|---|---|
| Rollout, 10 s `preStop` | 20/20 | 1 failure |
| 2 rollouts, 20 s `preStop` | — | 58 failures / 61 |
| 1 rollout | — | 70/70 |
| 2 rollouts | — | 80/81 |
| WebSocket (`v2`), deployment + 2 rollouts | 88/88 | 86/88 |

### Version `v3` (modified result, abandoned, see ADR-0009)

| Scenario | poll | result |
|---|---|---|
| **`v3` deployed with `scripts/deploy.sh`** (new image, the reference case) | **65/65** | **65/65** |
| 2 back-to-back rollouts, attempt 1 | 39/39 | 37/38 |
| 2 back-to-back rollouts, attempt 2 | 42/42 | 42/42 |
| 2 back-to-back rollouts, attempt 3 | 46/46 | 46/46 |
| Baseline, no deployment | 20/20 | 40/40 |

### Upstream version (`v4`, 2026-10-18), after ADR-0009

The `v2` and `v3` results above were on a **modified** result. Since the upstream components must stay unmodified, the original code was restored ([ADR-0009](../adr/0009-upstream-components-unmodified.md)): polling transport, `ClientIP` affinity + `externalTrafficPolicy: Local`, 20 s `preStop`, no graceful shutdown. Measured with `scripts/probe.sh`:

| Scenario | poll | result |
|---|---|---|
| Right after `az aks start` (pods `Ready`, no deployment in progress) | **~80 s without response** | **~80 s without response** |
| `v4` deployment (upstream code) | ok | 1 failure |
| `v5` deployment | 69/69 | 68/68 |
| **Rollback** to `v4` (`TAG=v4 SKIP_BUILD=1 scripts/deploy.sh`) | 65/66 | 66/66 |

- **Outage after restart**: both applications went down together, before any deployment. Pods were ready, but the Load Balancer had not finished routing to the recreated nodes. Wait for the pages to answer before a demo ([README](../../README.md)).
- **Updates**: 1 isolated failure per deployment in 2 cases out of 3. Zero errors is **not guaranteed** with the upstream code. For result, the most likely cause is Node.js exiting immediately on `SIGTERM` (the upstream code has no graceful shutdown), combined with affinity. The isolated poll failure during the rollback is unexplained (gunicorn shuts down gracefully). The possible improvement without touching the code is an Ingress with cookie affinity (ADR-0009, option B).

## Load test

### Method

| Item | Value |
|---|---|
| Tool | [k6](https://k6.io), Docker image `grafana/k6`, script [`scripts/load-test.js`](../../scripts/load-test.js) |
| Scenario | Each virtual user loads the voting page, votes (random choice), loads the results page, then waits 1 s |
| Load | Ramp from 10 to 50 then to **100 concurrent users**, over 3 min |
| Thresholds | Under 1 % errors, 95 % of requests under 500 ms |
| Generator | One machine in France (12 cores), to the public IPs in Spain Central |
| Monitoring | `kubectl top` and Redis queue length every 30 s; pod restarts before and after |
| Version | `v3` (modified result), 2026-10-15. Poll, worker and Redis are identical to upstream; only the result page has changed since |

```sh
POLL=http://<ip> RESULT=http://<ip> \
docker run --rm -i -e POLL -e RESULT grafana/k6 run - < scripts/load-test.js
```

### Results

| Measure | Value |
|---|---|
| Requests | 15,453 (85 req/s), including 5,151 votes (≈ 28 votes/s) |
| Errors | **0** (threshold < 1 % ✅) |
| Latency | median 174 ms, p95 **208 ms** (threshold < 500 ms ✅), max 6.45 s (a single isolated case) |
| Redis queue | **0** at every reading: the worker processes votes as fast as they arrive |
| Pod restarts | 0 |

Minimum latency is 145 ms. It comes mostly from the network path between France and Spain, not from processing.

Peak usage measured during the 100-user plateau:

| Pod | CPU | Memory | Compared to configuration |
|---|---|---|---|
| poll (×2) | 66–85m | 85–88 Mi | CPU above the request (50m), no limit so no throttling. Memory at **69 % of the limit** (128 Mi) |
| result (×2) | 14–15m | 36 Mi | Wide margin |
| worker | 15m | 58 Mi | Far below the request (256 Mi): oversized |
| redis | 21m | 7 Mi | — |
| postgres | 10m | 42 Mi | No `requests` defined |
| Nodes | 11–16 % CPU | 56–59 % memory | Memory is mostly used by AKS system components |

### Conclusions

- At 100 concurrent users the application meets the thresholds **with no error**, and **the limit was not reached**. The limiting factor in this test is the generator (1 iteration per second per user), not the cluster.
- **To adjust** (done on 2026-10-18, see the retrospective):
  - poll memory limit: 88 Mi out of 128 Mi, must be raised before heavier load, otherwise `OOMKilled` risk;
  - worker memory request: reduce it, e.g. to 128 Mi;
  - PostgreSQL `requests`: to define.
- The test adds **one fake voter per vote** (5,157 rows in `votes` after the test): k6 clears cookies on each iteration, so every vote arrives with a new `voter_id`. The table was emptied (`TRUNCATE votes`) after the test.

### Upstream version (`56d0fd8`, 2026-10-18)

Same scenario, on a deployment done **from scratch** (namespace deleted, then only the README commands), with adjusted resources and pinned `redis:8.10.2` and `postgres:18.6` tags:

| Measure | `v3` (modified result) | **Upstream version** |
|---|---|---|
| Requests | 15,453 (85 req/s) | 14,793 (82 req/s), including 4,931 votes |
| Errors | 0 | **0** |
| p95 latency | 208 ms | **260 ms** (threshold 500 ms ✅), max 1.52 s |
| Redis queue | 0 | 0 |
| Restarts | 0 | 0 |
| poll, max per pod | 85m, 88 Mi | 109m, 89 Mi, i.e. **35 % of the new limit** (256 Mi) |
| result, max per pod | 14–15m on each pod | **2m and 33m** |

- **Unbalanced load between result pods**: the generator has a single IP, so `ClientIP` affinity always sends it to the same pod. With real visitors, each with their own IP, load spreads. But an audience behind one NAT (a room, a campus) would all land on a single pod.
- Latency is slightly higher than with `v3`: Socket.IO's polling transport makes more requests. It stays within the threshold.
- The `votes` table was emptied after the test (4,933 test rows).

### HPA autoscaling (`73f6937`, 2026-10-28)

Same scenario, with the HPA from [ADR-0012](../adr/0012-autoscaling-hpa-poll-result.md) (2 to 4 pods, 70 % CPU target, poll request at 100m), right after restarting the cluster. Evolution read with `kubectl get hpa -n bernstein` every 15 s:

| Moment | poll (CPU / pods) | result (CPU / pods) |
|---|---|---|
| Test start | 5 % / 2 | 5 % / 2 |
| Ramp to 50 users | 42 % / 2 | 18 % / 2 |
| 100 users | **95 % / 2 → 3** | 30 % / 2 |
| Test end | 1 % / 3 | 2 % / 2 |
| ≈ 2 min after the end | 2 % / **3 → 2** | 2 % / 2 |

| Measure | 2026-10-18 (2 fixed pods) | HPA, 1st run (cluster just restarted) | **HPA, 2nd run (20 min later)** |
|---|---|---|---|
| Requests | 14,793 | 14,343 (79 req/s) | **16,836 (93 req/s)** |
| Errors | 0 | 18 (0.12 %) | **0** |
| p95 latency | 260 ms | 535 ms (threshold 500 ms ❌), max 3.76 s | **170 ms** ✅, max 1.01 s |
| poll | 2 pods | 95 % → 3 pods | 90 % → 3 pods |

- The HPA works both ways: scale-up to 3 pods under load, back to 2 after the 120 s stabilisation window.
- result stays at 2: it uses little CPU, the target is not reached.
- **The 1st run's errors do not reproduce**: rerun 20 minutes later on the same cluster, the test gives 0 errors and a p95 of 170 ms, with the same scale-up to 3 pods. Starting the 3rd pod is therefore not the cause; the most likely explanation is the freshly restarted cluster (nodes and pods recreated a few minutes earlier). Takeaway for demos: start the cluster **at least 15 minutes ahead**.

## Limits

- **Small sample** for the update tests: a few hundred requests, from a single client, over a few attempts. These measurements show the fixes work; they do not prove a zero error rate.
- **One residual failure** on result when a second deployment starts before the first ends (1 attempt out of 3). Cause unknown. Leads: endpoint propagation delay on AKS, longer `preStop`.
- **Maximum capacity is unknown**: the load test did not push the cluster to its limit. Next step: several generators or a shorter `sleep`, until the first threshold is crossed.
- The load test does not measure result's Socket.IO connections (live updates). Only page loads are measured.
- Problem #1 was only seen after public exposure. A load test before exposure would have caught it earlier.
