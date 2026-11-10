# ADR-0004: Exposing poll and result through two `LoadBalancer` Services

- **Status:** Accepted — `result` Service configuration (affinity, `Local`) superseded by [ADR-0005](0005-result-websocket-without-affinity.md)
- **Date:** 2026-10-15
- **Deciders:** Ridwane777

## Context

Requirement: the Poll and Result pages must be "*accessible from the outside world*"; giving out "*the external IP addresses*" is enough, no domain name or HTTPS is required. An update must cause no error for a client polling the application continuously.

Technical constraint: result uses Socket.IO with **polling transport only** (`result/views/app.js`: `transports:['polling']`). Each session (`sid`) only exists on the pod that created it. With 2 replicas, all requests from one client must reach the same pod (session affinity).

## Options considered

| Criterion | **A. 2 `LoadBalancer` Services** | B. Traefik Ingress | C. AKS App Routing (managed NGINX Ingress) |
|---|---|---|---|
| Public IPs | 2 | 1 | 1 |
| Estimated public IP cost | ~2 × 0.12 €/day | ~0.12 €/day, plus controller resources | ~0.12 €/day |
| Affinity for result | `sessionAffinity: ClientIP`, native | Cookie to configure on the Ingress | Cookie to configure |
| HTTPS / domain | No, Service by Service | Centralised (cert-manager) | Centralised |
| Component to install | None | Controller (Helm) | Add-on (`az aks approuting enable`) |
| Redeployment by someone else | `kubectl apply -f k8s/` | One more install step | One more Azure step |

## Decision

**Option A.** The `poll` and `result` Services become `type: LoadBalancer`. Azure creates a public IP for each on its Standard Load Balancer.

The `result` Service is configured with:

- `sessionAffinity: ClientIP`: a given client is always sent to the same pod;
- `externalTrafficPolicy: Local`: traffic is only sent to nodes hosting a result pod, **without source NAT**. The Service therefore sees the real client IP. With the default policy (`Cluster`), a packet can cross another node and arrive with that node's IP, which breaks affinity.

## Verification (2026-10-15)

- `poll` → `203.0.113.10`, `result` → `203.0.113.20`: HTTP 200 on both. These IPs change if the Services are recreated.
- 4 successive Socket.IO session openings from the same client: the `sid`s are sequential (`…AAAD`, `…AAAE`, `…AAAF`, `…AAAG`). This counter is per server process, so all 4 requests were served by the same pod.

## Consequences

### ✅ Gained

- Requirement covered with no extra component. Everything deploys with `kubectl apply -f k8s/`.
- result affinity works with no proxy configuration.
- The Azure Load Balancer health-checks the nodes. With readinessProbes, a pod being replaced receives no traffic.

### ❌ Lost / risks

- **No HTTPS**: votes travel in clear text. Acceptable for a demo, not for a real election.
- **No domain name**: IPs are dynamic and change if the Service is deleted. A static Azure IP is possible (`loadBalancerIP` + resource group annotation).
- **One IP per application**: cost and exposed surface grow with the number of applications.
- **Coarse `ClientIP` affinity**: all users behind the same NAT (campus, company) land on the same pod.
- **`externalTrafficPolicy: Local`**: a node with no result pod receives no traffic. If both pods are on the same node, that node carries all the load, hence a pod spreading rule.

### When to change

An Ingress (option B or C) becomes preferable as soon as **HTTPS**, a **domain name**, or more than **2 or 3 exposed applications** are needed. result affinity would then use an Ingress cookie.

## Links

- [ADR-0001](0001-platform-aks-acr.md), [ADR-0003](0003-yaml-manifests-postgres-statefulset.md)
- Manifests: `k8s/30-poll.yaml`, `k8s/50-result.yaml`
