# Retrospective

A look at **the whole project**, from bootstrap to measured deployment: what we would keep, what could have been done better to reduce cost, time and risk, and the next actions.

## What we would keep

- **Measuring before concluding.** Zero downtime was checked with a `curl` loop, capacity with k6. Without these measurements, two serious defects would have gone unnoticed: poll restarting in a loop, and a 3-minute outage on result.
- **ADRs written when the decision is made**, superseded rather than rewritten (0004 → 0005). The history shows what was learned.
- **Immutable image tags** and the single `scripts/deploy.sh` script: a deployment is reproducible and traceable.
- **Secrets outside the repository**, managed identity for ACR: no credentials in git.
- **A managed service (AKS)** rather than a hand-built cluster: no hours spent on etcd or certificates.

## What could have been done better

| Finding | Consequence | Concrete alternative | When it becomes preferable | Its cost |
|---|---|---|---|---|
| Platform chosen **before** checking region policies, allowed sizes and quotas | 4 regions tried, a half-created cluster, a deleted resource group ([ADR-0002](../adr/0002-region-spain-central.md)) | Check first: `az policy assignment list`, `az vm list-skus`, `az vm list-usage` | Always, on a restricted subscription (free credit, corporate) | 15 min |
| **Default OS disk** (128 GB Premium) | 1.26 €/day, 30 % of the bill ([docs/costs](../costs/README.md)) | `--node-osdisk-size 30` when creating the cluster | As soon as you pay for the cluster yourself | None at creation. Recreate the node pool afterwards |
| **VM for the bootstrap** (Minikube) | 12.54 € and troubleshooting time (892 MB VM, resizing) | `kind` or Minikube locally, or the AKS cluster directly | If the local machine has ≥ 8 GB RAM | 0 € |
| **Load test after exposure**, not before | The gunicorn defect (1 *sync* worker) was only seen when a user hit it | Run `scripts/load-test.js` before any exposure | Always, before going live | 5 min per test |
| **Constraint identified late**: result was modified (WebSocket, graceful shutdown) before settling on keeping the upstream application unmodified | Two ADRs (0005 then 0009) and a return to the upstream code with its affinity fragility | Pin down **all** constraints before architecture choices. Within them, Ingress cookie affinity is the only improvement possible without touching the code | Whenever a component must be used as-is | Install and maintain an Ingress controller |
| **`envsubst` on plain YAML** | `kubectl apply -f k8s/` no longer works alone, and registry and tag are handled by a home-made script | **Kustomize** (`kustomize edit set image`), built into kubectl | As soon as an image or registry must be parameterised | A `kustomization.yaml` file. Supersede ADR-0003 |
| **Manual deployment** from a developer's machine | Depends on the machine and locally installed tools | **CI/CD** (GitHub Actions): build, push and deploy on every commit to `main`, with Azure federated identity (OIDC) | As soon as there is more than one developer or more than one deployment a week | ≈ 1 day to set up |
| **Floating tags** `redis:8`, `postgres:18` | A new version can arrive without being chosen (Redis 8.10.2 observed) | Exact tags or `@sha256` digests | Always in production | Update tags by hand |
| **No monitoring** | Incidents were seen by a user or by our tests, never by an alert | Prometheus + Grafana (kube-prometheus-stack) or Azure Monitor (paid) | As soon as the application must run unattended | CPU and memory in the cluster, or ≈ 2 €/GB ingested with Azure Monitor |
| **No PostgreSQL backup** | Votes lost if the disk is lost ([ADR-0003](../adr/0003-yaml-manifests-postgres-statefulset.md)) | `pg_dump` CronJob to Azure Blob, or Azure Database for PostgreSQL | As soon as votes have value | A few cents a month on Blob, ≈ 15–25 €/month for the managed database |
| **No HTTPS** | Votes and cookie in clear text ([docs/legal](../legal/README.md)) | Ingress + cert-manager + domain name | Before any real use | A domain name (≈ 10 €/year) and a controller to maintain |

## What would have reduced…

- **…costs:** 30 GB OS disk; local bootstrap; stopping the cluster between sessions (≈ 3.3 €/day saved); a single public IP with an Ingress.
- **…time:** checking Azure constraints before writing the platform ADR; reading the application code (Socket.IO transport, gunicorn server) before choosing the exposure; a load test from the first deployment.
- **…risks:** HTTPS; backups; pinned image tags; monitoring with alerts; PodDisruptionBudget.

## Next actions

| Priority | Action | Related document |
|---|---|---|
| 1 | Read the measured AKS cost in Cost Management | [docs/costs](../costs/README.md) |
| ✅ | Resources adjusted: poll memory limit 256 Mi, worker request 128 Mi, PostgreSQL and Redis `requests` (2026-10-18) | [docs/performance](../performance/README.md) |
| ✅ | Tags pinned: `redis:8.10.2`, `postgres:18.6` (2026-10-18) | [docs/dependencies.md](../dependencies.md) |
| ✅ | PodDisruptionBudgets on poll and result, `k8s/60-disruption-budgets.yaml` (2026-10-18) | [ADR-0008](../adr/0008-zero-downtime-updates-and-resources.md) |
| ✅ | Deployment from a link: Jenkins (tested), GitHub Actions ready but minutes exhausted (2026-10-20) | [ADR-0010](../adr/0010-github-actions-deployment.md), [ADR-0011](../adr/0011-jenkins-deployment.md) |
| ✅ | HPA autoscaling of poll and result, 2 to 4 pods, tested under load (2026-10-28) | [ADR-0012](../adr/0012-autoscaling-hpa-poll-result.md) |
| 5 | Move to Kustomize | ADR to write |
| 6 | Set up HTTPS and PostgreSQL backups before any real use | [docs/legal](../legal/README.md) |
