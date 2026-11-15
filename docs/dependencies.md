# Dependencies

Surveyed on 2026-10-15 in the repository and on the cluster.

## Providers and services

| Dependency | Use | Known quota / limit | If unavailable |
|---|---|---|---|
| Microsoft Azure | AKS, ACR, disks, public IPs | 100 $ credit. **6 regional vCPUs**. Regions allowed by policy: Sweden Central, Austria East, Germany West Central, Spain Central, Italy North ([ADR-0002](adr/0002-region-spain-central.md)) | No more deployments. The repository stays portable (standard Kubernetes manifests, only the `az` scripts change) |
| Docker Hub | Base images `python:3.14-slim`, `node:24-slim`, `maven`, `eclipse-temurin:25-jre`, `redis:8.10.2`, `postgres:18.6` | Anonymous pull rate limit | Builds and Redis / PostgreSQL pod starts fail |
| Jenkins (`jenkins/jenkins:lts`) on a VPS (jenkins.example.com:8090) | Deploy, stop and start from a link (`Jenkinsfile`, [ADR-0011](adr/0011-jenkins-deployment.md)) | VPS resources (8 vCPU, 23 GB); *Docker Pipeline* plugin required | No deployment link; the command-line procedure remains available |
| GitHub Actions | Alternative to Jenkins (`.github/workflows/deploy.yml`, [ADR-0010](adr/0010-github-actions-deployment.md)) | **Organisation minutes exhausted** (as of 2026-10-20) | Workflow unusable until the monthly reset |
| Public CDNs (Google, jQuery, BootstrapCDN) | AngularJS, jQuery, Font Awesome, loaded by the browser | - | Pages without style or interactivity (see [docs/legal](legal/README.md), risks 3 and 4) |

## Images and versions

| Image | Tag used | Version actually pulled | Risk |
|---|---|---|---|
| `redis` | `8.10.2` (pinned on 2026-10-18) | 8.10.2 | None. Before: `8`, a floating tag |
| `postgres` | `18.6` (pinned on 2026-10-18) | 18.6 | None. Before: `18`. A major version change would require a data migration |
| `poll`, `worker`, `result` | one tag per deployment (`v3`, git hash) | - | None: tags are immutable |

Remaining improvement: pin digests (`redis@sha256:…`) to guard against a republished tag.

## Libraries

| Application | Main dependencies | Licences |
|---|---|---|
| poll | Flask 3.1.3, redis-py 8.1.0, gunicorn 26.2.0 | BSD-3-Clause, MIT, MIT |
| worker | Jedis 8.0.1, PostgreSQL driver 42.7.13, org.json 20260814 | MIT, BSD-2-Clause, Public Domain (JSON License) |
| result | Express 5, Socket.IO 4.8, pg 8, async 3 (105 packages in total in `package-lock.json`) | 98 MIT, 6 ISC, 1 BSD-3-Clause |
| Browser | AngularJS 1.4.5, jQuery (`latest`), Font Awesome 4.4.0 | MIT, MIT, SIL OFL / MIT |
| Services | Redis 8 | RSALv2 / SSPLv1 / AGPLv3 (your choice) |
| | PostgreSQL 18 | PostgreSQL License (permissive) |

## Secrets

| Secret | Where it lives | In the repository? |
|---|---|---|
| Azure credentials | `~/.azure/` on the operator's machine | No |
| Cluster access | `~/.kube/config` | No |
| ACR access from AKS | Cluster managed identity (`--attach-acr`), no password | No |
| `POSTGRES_PASSWORD` | Kubernetes Secret `postgres-secret`, created by `scripts/deploy.sh` from an environment variable | No |
| `bernstein-jenkins-deploy` service principal password (Contributor on `bernstein-spain-rg`) | Jenkins credentials `azure-deploy-sp`, masked in logs. **Expires** (1 year by default): `az ad sp credential reset` | No |
| GitHub token with read access to the repository | Jenkins credentials `github-bernstein`. Expiry chosen at creation | No |
| GitHub Actions Azure access | OIDC federated identity, no password | No |

## Operator tools

`az` (Azure CLI), `docker`, `kubectl`, `envsubst` (gettext). Jenkins only needs Docker: the other tools are in the `ci/Dockerfile` image. For measurements: `curl` (`scripts/probe.sh`) and `grafana/k6` (`scripts/load-test.js`).
