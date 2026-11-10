# ADR-0007: A single replica for the worker

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** Ridwane777

## Context

The worker reads the Redis queue (`BLPOP`) and writes each vote to PostgreSQL with an UPSERT: one row per voter, the voter's last vote wins. It receives no connections, so it has no Service (see `docs/kubernetes-guide.md`, § 7). It only exposes `/healthz` and `/readyz` on port 80 for the probes.

## Options considered

| Option | ✅ | ❌ |
|---|---|---|
| **A. 1 replica** | Vote order for a given voter is preserved | No parallel processing; the queue builds up during a restart |
| B. N replicas | Multiplied throughput, tolerates losing a pod | `BLPOP` spreads votes across workers: two successive votes from one voter can be written out of order, and the old vote can overwrite the new one |
| C. N replicas partitioned by voter | Throughput and order preserved | Code change (several queues, voter hashing) |

## Decision

**Option A**, `k8s/40-worker.yaml`:

- 1 replica;
- `maxSurge: 1` and `maxUnavailable: 0`: during an update the new worker starts before the old one stops;
- a `startupProbe` giving the JVM up to 2 minutes to start;
- PostgreSQL password read from the `postgres-secret` Secret.

## Consequences

### ✅ Gained

- Correct results: a voter's last vote is always the one that counts.
- Votes are not lost while the worker is absent: they wait in Redis (5 pending votes, all processed on start).

### ❌ Lost / risks

- **Throughput limited to one process.** Not measured: there is no load test yet (see [docs/performance](../performance/README.md)).
- **During an update, two workers coexist for a few seconds** (`maxSurge: 1`). Order is then not strictly guaranteed. Negligible impact: one voter would have to vote twice in that window.
- If the pod goes down, displayed results lag until it restarts. No vote is lost.

### When to change

If the Redis queue grows durably under load, move to option C.
