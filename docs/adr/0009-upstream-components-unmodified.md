# ADR-0009: Upstream application components left unmodified

- **Status:** Accepted
- **Date:** 2026-10-18
- **Deciders:** Ridwane777
- **Supersedes:**
  - [ADR-0005](0005-result-websocket-without-affinity.md) entirely;
  - [ADR-0008](0008-zero-downtime-updates-and-resources.md) for result only: the graceful shutdown in `server.js` and the 10 s `preStop`.

## Context

This repository is about **deploying** the voting application, not maintaining a fork of it. Deliberate constraint: the five components (Poll, Redis, Worker, PostgreSQL, Result) run **exactly as published upstream**, so the application can be updated independently by dropping in a new version, with no patches to re-apply.

ADR-0005 had modified two result files:

- `views/app.js`: WebSocket transport, percentage computation;
- `server.js`: graceful shutdown.

A comparison with the original source archive confirmed **these two files were the only ones modified**.

## Options considered

| Option | ✅ | ❌ |
|---|---|---|
| **A. Upstream code + `ClientIP` affinity and `externalTrafficPolicy: Local`** | No component modified; nothing to install; configuration already measured (ADR-0004) | Measured fragility during back-to-back rollouts; coarse affinity behind a NAT |
| B. Upstream code + Ingress with cookie affinity | Reliable affinity, single IP | Controller to install (one more step to redeploy), to be measured again |
| C. Upstream code + a single result replica | No affinity needed | No redundancy, 2 pods coexist during an update |
| D. Keep the patches | More robust | Breaks the constraint: a fork to maintain on every upstream update |

## Decision

- **Option A.** `project-applications/` is restored to the original source, checked with `diff -rq`.
- `k8s/50-result.yaml` gets `sessionAffinity: ClientIP` and `externalTrafficPolicy: Local` back, with a 20 s `preStop` and `terminationGracePeriodSeconds: 40`.
- poll's gunicorn command override is kept: it is **deployment configuration** in the manifest; the image and the code stay upstream.

## Consequences

### ✅ Gained

- Constraint met: all 5 components are upstream versions and can be upgraded independently.

### ❌ Lost / risks

- **The display bug is back**: "-1 %" possible in result (e.g. with 1, 4, 1 and 0 votes). It is an upstream defect, to report upstream, not to patch here.
- **Affinity fragility is back** during result rollouts (see [docs/performance](../performance/README.md)).
- **No more graceful shutdown** of Node.js on `SIGTERM`: only `preStop` protects in-flight requests.
- **Duplicate `scores` handlers** on each Socket.IO reconnection: upstream defect, no visible effect on the display.
- **Interpretation risk** on poll's gunicorn command: if it is ever seen as a modification, reverting to the image command brings back the crash under idle connections ([docs/performance](../performance/README.md), problem #1).
