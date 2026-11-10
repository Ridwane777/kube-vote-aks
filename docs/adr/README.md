# Architecture Decision Records

One decision per file, MADR format. An accepted ADR is never rewritten: if a decision changes, a new ADR supersedes it and the old one moves to the status "Superseded by ADR-xxxx".

| # | Decision | Status | Date |
|---|---|---|---|
| [0001](0001-platform-aks-acr.md) | Platform: AKS + ACR, 2 `B2als_v2` nodes | Accepted (region superseded by 0002) | 2026-10-15 |
| [0002](0002-region-spain-central.md) | Spain Central region, `bernstein-spain-rg` resource group | Accepted | 2026-10-15 |
| [0003](0003-yaml-manifests-postgres-statefulset.md) | Plain YAML manifests, PostgreSQL as a StatefulSet in AKS | Accepted | 2026-10-15 |
| [0004](0004-loadbalancer-exposure.md) | Exposing poll and result through 2 `LoadBalancer` Services | Accepted (result Service superseded by 0005) | 2026-10-15 |
| [0005](0005-result-websocket-without-affinity.md) | result over WebSocket, without session affinity | Superseded by 0009 | 2026-10-15 |
| [0006](0006-ephemeral-redis-without-password.md) | Ephemeral Redis, without disk or password | Accepted | 2026-10-15 |
| [0007](0007-single-worker-replica.md) | A single replica for the worker | Accepted | 2026-10-15 |
| [0008](0008-zero-downtime-updates-and-resources.md) | Zero-downtime updates, probes and resources | Accepted (result part superseded by 0009, HPA added by 0012) | 2026-10-15 |
| [0009](0009-upstream-components-unmodified.md) | Upstream components left unmodified, `ClientIP` affinity restored for result | Accepted | 2026-10-18 |
| [0010](0010-github-actions-deployment.md) | Deployment triggered from GitHub Actions (OIDC, no secret) | Accepted, Azure configuration pending | 2026-10-20 |
| [0011](0011-jenkins-deployment.md) | Deployment triggered from Jenkins (GitHub Actions minutes exhausted) | Accepted, tested (build `80cb6c5`) | 2026-10-20 |
| [0012](0012-autoscaling-hpa-poll-result.md) | HPA autoscaling of poll and result, 2 to 4 pods (70 % CPU) | Accepted, tested | 2026-10-28 |
