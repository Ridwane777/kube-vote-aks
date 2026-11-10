# ADR-0011: Deployment triggered from Jenkins

- **Status:** Accepted, configured and tested on 2026-10-20 (build `80cb6c5` succeeded)
- **Date:** 2026-10-20
- **Deciders:** Ridwane777
- **Complements:** [ADR-0010](0010-github-actions-deployment.md). The GitHub Actions workflow is kept and becomes usable again as soon as the organisation has minutes again.

## Context

[ADR-0010](0010-github-actions-deployment.md) added deployment from a link with GitHub Actions. The **organisation's GitHub Actions minutes are exhausted**: workflows no longer run on GitHub's runners. A **Jenkins server on a VPS** is already available.

## Options considered

| Option | ✅ | ❌ |
|---|---|---|
| **A. Existing Jenkins on the VPS** | No server to create or pay for; "Build with Parameters" link; `Jenkinsfile` versioned in the repository | A **secret** (service principal password) stored in Jenkins; the Jenkins UI is exposed to the Internet; depends on a VPS outside this project |
| B. Self-hosted GitHub Actions runner | Same workflow, no minutes consumed, secretless OIDC | Needs repository **admin rights** to register the runner, which are not available |
| C. Wait for the monthly minutes reset | Nothing to do | Uncertain date, minutes shared with other repositories |
| D. Jenkins on a new Azure VM | Independent of personal machines | ≈ 1 €/day more, and the last available vCPU quota |

## Decision

**Option A**, `Jenkinsfile` at the root:

- **nothing is installed in Jenkins**: steps run inside a versioned tools image, `ci/Dockerfile` (`az`, `kubectl`, `envsubst`, `git`), started by the *Docker Pipeline* plugin with the host's Docker socket. The existing Jenkins (`jenkins/jenkins:lts`, Docker socket and binary already mounted, plugin already installed) is not modified;
- `TAG` (empty = current commit) and `ROLLBACK` (redeploy without rebuilding, `SKIP_BUILD=1`) parameters, the tag being validated before use;
- Azure login with a **service principal** holding the *Contributor* role scoped to the `bernstein-spain-rg` group. Its password is in the Jenkins *Credentials* (`azure-deploy-sp`), masked in logs, **never in the repository**;
- each build's Azure and kubectl state is isolated in a temporary directory, then removed at the end (`az logout`);
- cluster started if stopped, and `POSTGRES_PASSWORD` generated during the build, as in ADR-0010;
- `disableConcurrentBuilds` prevents two simultaneous deployments.

## Consequences

### ✅ Gained

- Deployment and rollback from a link, despite exhausted GitHub Actions minutes.
- Same deployment logic (`scripts/deploy.sh`) on the command line, with GitHub Actions and with Jenkins.
- No secret in the repository.

### ❌ Lost / risks

- **One more secret to protect**: the service principal password. It expires (1 year by default) and must be renewed (`az ad sp credential reset`). If it leaks, the resource group is open until it is revoked.
- **Attack surface**: an Internet-facing Jenkins must be kept up to date (Jenkins and plugins) and restricted to authorised users.
- **Dependency on the VPS**: if it is down, the link stops working. The command-line procedure remains the reference.
- The VPS needs Docker and enough memory to build the worker's Java image (Maven).
