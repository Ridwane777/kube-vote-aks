# ADR-0003: Plain YAML manifests, PostgreSQL as a StatefulSet in AKS

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** Ridwane777

## Context

The voting app needs a persistent PostgreSQL 18 database, with the `votes` table created by `schema.sql`. It must be redeployable from the repository onto an empty AKS cluster (ADR-0001, ADR-0002). We also need to choose how to write and apply the Kubernetes manifests.

Constraints: limited Azure credit, and Kubernetes was being learned during the project.

## Options considered

### PostgreSQL hosting

| Option | ✅ | ❌ |
|---|---|---|
| **A. StatefulSet + PVC (Azure disk) in AKS** | No cost beyond the nodes and the disk; everything is in the manifests; shows how to run a stateful service | Backups, upgrades and high availability are on us; single instance |
| B. Azure Database for PostgreSQL (Flexible Server) | Automatic backups, optional high availability, managed patches | ~15–25 €/month minimum (estimate), resource outside the cluster created separately, less Kubernetes to show |

### Manifest format

| Option | ✅ | ❌ |
|---|---|---|
| **A. Plain YAML, numbered files in `k8s/`** | Readable, no extra tool, `kubectl apply -f k8s/` | Values repeated across files, no per-environment variants |
| B. Kustomize | Built into kubectl, per-environment overlays | One more concept, useless with a single environment |
| C. Helm | Templates, versions, release rollback | Heavy for a single application, hides Kubernetes syntax |

## Decision

- **PostgreSQL: 1-replica StatefulSet**, with a `volumeClaimTemplate` (dynamic Azure disk) and a Service. Password in the `postgres-secret` Secret, created outside the repository.
- **Manifests: plain YAML** in `k8s/`, numbered in apply order (`00-namespace.yaml`, …), all in the `bernstein` namespace.

## Consequences

### ✅ Gained

- Full deployment in one command, with no extra Azure resource.
- No extra cost for the database.

### ❌ Lost / risks

- **No automatic backup**: losing the disk loses the votes. Possible fix: a `pg_dump` CronJob, or switching to option B.
- **Single point of failure**: one PostgreSQL pod. While it restarts, the worker cannot write.
- **`ReadWriteOnce` disk**: attached to one node at a time, and the pod takes longer to restart if it moves to another node.
- **The password is set on first start**: changing the Secret does not change an already-initialised database.

## Links

- [ADR-0001](0001-platform-aks-acr.md), [ADR-0002](0002-region-spain-central.md)
