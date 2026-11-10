# Business plan

Kube Vote AKS is a portfolio project. This document looks at what the work would become if it were offered as a service. Cost figures come from [docs/costs](../costs/README.md) and capacity figures from [docs/performance](../performance/README.md). Market assumptions are not verified and are marked as such.

## Problem

An event organiser (conference, class, company meeting, association) wants to **poll the audience live** and show results on screen in real time. Existing tools are third-party hosted services, often outside the European Union, with paid plans per organiser.

## Solution

A live voting application (voting page and real-time results page), **deployable in one command** on the customer's Kubernetes cluster or on a cluster we run:

- progressive, measured updates: 0 to 1 failed request per deployment with the upstream code ([docs/performance](../performance/README.md));
- hosting in the EU (Spain);
- no account required from voters, only a pseudonymous identifier.

## Market and target customers (assumptions)

| Segment | Need | Sensitivity |
|---|---|---|
| Schools and universities | In-class polls | Price, learner data (GDPR) |
| Companies (internal meetings) | EU hosting, or on their own infrastructure | Data sovereignty |
| Associations and local authorities | Simple consultations | Price |

## Competition

| Competitor | Strengths | Our difference |
|---|---|---|
| Slido, Mentimeter, Wooclap, Kahoot | Full products (quizzes, word clouds, PowerPoint and Teams integrations), brand awareness | Deployment on the customer's infrastructure or in the EU, source code under control, known infrastructure cost |
| Forms (Google Forms, Microsoft Forms) | Free, familiar | Live results on screen |

Our product is far poorer in features: 4 fixed choices, a single question.

## Business model (assumption)

| Offer | Content | Indicative price |
|---|---|---|
| Self-hosted | Manifests, scripts, documentation, e-mail support | Annual licence per organisation |
| Managed per event | Dedicated cluster for the event | Flat fee per event |
| Managed yearly | Shared cluster, several polls | Monthly subscription |

### Unit cost (measured and estimated)

| Item | Value | Source |
|---|---|---|
| Running cluster cost | ≈ 4.3 €/day | Estimated, public Azure prices |
| Demonstrated capacity | 100 concurrent users, ≈ 28 votes/s, 0 errors, p95 208 ms, cluster at 16 % CPU at most | Measured (k6) |
| One-day event (cluster on 24 h, stopped otherwise) | ≈ 4.3 € of infrastructure, plus ≈ 1 €/day of fixed costs (IPs, ACR) | Estimated |

Maximum capacity is unknown: the load test did not reach the cluster's limit. At 100 voters, infrastructure costs about **4 cents per voter per day**, and it falls as the audience grows, since the cluster is not saturated.

## SWOT

| | Positive | Negative |
|---|---|---|
| **Internal** | **Strengths**: reproducible one-command deployment; measured progressive updates and rollback; EU hosting; known, controlled costs | **Weaknesses**: minimal features; zero errors not guaranteed during result updates (upstream code kept unmodified); no HTTPS; no backups; outdated front-end libraries ([docs/legal](../legal/README.md)); a single person knows how to operate it |
| **External** | **Opportunities**: demand for data sovereignty (GDPR, public sector); organisations already running Kubernetes | **Threats**: established competitors, free for small use; dependency on Azure and its quotas; licence changes (Redis) |

## Roadmap

| Step | Content | Technical prerequisite |
|---|---|---|
| 1. Harden | HTTPS, backups, monitoring, pinned tags | [Retrospective](../retrospective/README.md), actions 3 to 6 |
| 2. Minimum sellable product | Configurable questions and choices (`OPTION_A` to `OPTION_D` already exist), several polls | Changes to poll and result |
| 3. Industrialise | CI/CD, Kustomize, one namespace per customer | ADR to write |
| 4. Scale | Autoscaling (HPA, then node autoscaler), measuring maximum capacity | Load test up to saturation |
