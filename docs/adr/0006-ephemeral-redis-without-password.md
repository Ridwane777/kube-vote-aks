# ADR-0006: Ephemeral Redis, without disk or password

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** Ridwane777

## Context

Redis is the queue between poll (`RPUSH votes`) and the worker (`BLPOP votes`). The worker drains the queue continuously and writes each vote to PostgreSQL, which holds the reference data. The application README accepts a password-protected Redis (`REDIS_PASSWORD`) but does not require it.

## Options considered

| Option | ✅ | ❌ |
|---|---|---|
| **A. 1 replica, no disk, no password** | Simple, instant start, no disk to pay for, no extra Secret | Pending votes lost if Redis restarts; any pod in the cluster can read and write the queue |
| B. AOF persistence on a PVC (StatefulSet) | Pending votes survive a restart | Disk, StatefulSet, slower disk reattach when moving nodes |
| C. Password (`requirepass`) in a Secret | Only clients with the password reach the queue | One more Secret, to inject into Redis, poll and the worker |
| D. Replicated Redis (Sentinel or operator) | High availability | Disproportionate complexity for a pass-through queue |

## Decision

**Option A**, `k8s/20-redis.yaml`: a 1-replica Deployment, `redis:8` image, with a `redis-cli ping` readinessProbe. The Service is ClusterIP, so Redis is **not exposed** outside the cluster.

## Consequences

### ✅ Gained

- No storage cost, no extra Secret.
- In normal operation the queue empties within milliseconds: there is almost nothing to lose.

### ❌ Lost / risks

- **Pending votes lost** if Redis restarts while the worker is down. Measured: 5 votes stayed pending while the worker was not deployed, then were all processed when it arrived.
- **No authentication**: any pod in the cluster can read or inject votes. The risk is limited to inside the cluster.
- **Interruption during a Redis update**: single replica, and poll is removed from its Service (`/readyz` returns 503) while Redis does not answer.

### When to change

- Add option C (password) and a **NetworkPolicy** (only poll and the worker reach Redis) as soon as other applications share the cluster.
- Move to option B if losing a few votes becomes unacceptable.
