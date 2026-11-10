# Legal analysis

This document covers the data processed by the voting application, the legal risks and the measures to take before a public launch. The project is a **portfolio project**, deployed temporarily for demonstrations. A real production launch would require the actions marked "to do".

## Data processed

Surveyed in the code and on the deployment (2026-10-15):

| Data | Where | Personal? | Retention |
|---|---|---|---|
| `voter_id`: random identifier (UUID) in a cookie | Browser, Redis (in transit), PostgreSQL (`votes.id`) | **Yes, pseudonymous** (GDPR, recital 26): it identifies a browser | Session cookie (no `Max-Age`, deleted when the browser closes). In the database: **no limit** |
| Vote choice (a, b, c or d) | PostgreSQL (`votes.vote`) | Yes, linked to the `voter_id` | No limit |
| Visitor IP address | TCP connections to the Azure Load Balancer and the pods | Yes | Not logged by the application: gunicorn and Express have no access log enabled |
| IP address sent to third-party CDNs | `ajax.googleapis.com` (AngularJS), `code.jquery.com` (jQuery), `maxcdn.bootstrapcdn.com` (Font Awesome) | Yes | Per provider |

No identity data (name, e-mail, account) is collected.

## Risks and measures

| # | Risk | Severity | Measure |
|---|---|---|---|
| 1 | **No HTTPS**: cookie and votes travel in clear text and can be read or altered on the network | High | To do: TLS (Ingress + cert-manager, see [ADR-0004](../adr/0004-loadbalancer-exposure.md)), then a `Secure` cookie |
| 2 | **Cookie without `HttpOnly` or `SameSite`** | Medium | To do: `httponly=True, samesite='Lax'` in `poll/app.py` |
| 3 | **Transfers to third-party CDNs** (Google, jQuery, BootstrapCDN) without informing the visitor. Google is subject to US law | Medium | To do: serve these files from the application, or inform the visitor in the privacy policy |
| 4 | **Outdated front-end libraries**: AngularJS 1.4.5 (end of support end of 2021, known XSS flaws), `jquery-latest` (old frozen version) | Medium | To do: update or remove these dependencies |
| 5 | **Unlimited retention** of votes | Low | To do: define a period (e.g. delete votes 30 days after the poll closes) |
| 6 | **Technical banners**: `Server: gunicorn` and `X-Powered-By: Express` headers | Low | To do: hide them (gives less information to an attacker) |
| 7 | **The vote is not a certified ballot**: one voter can vote several times by deleting their cookie | Information | State it in the terms of use: indicative poll, not an official ballot |

### Cookie and consent

The `voter_id` cookie is only used so that a browser has a single vote, the last one counting. It is necessary for the service requested by the user. Under the CNIL's position on trackers, it **probably** falls under the consent exemption (article 82 of the French Data Protection Act). Information remains mandatory: it must appear in the privacy policy. This qualification must be reviewed if the identifier is ever used for anything else.

## Hosting and processors

| Processor | Role | Location |
|---|---|---|
| Microsoft Azure | AKS cluster, ACR registry, disks, public IPs | **Spain Central** (European Union), see [ADR-0002](../adr/0002-region-spain-central.md) |
| Google, jQuery Foundation (StackPath), BootstrapCDN | JavaScript and CSS files loaded by the browser | Outside the project's control |

## Draft privacy policy

> **Who processes your data?** Ridwane777, author of the Kube Vote AKS project, as part of a portfolio demonstration.
>
> **What data?** A random identifier stored in a session cookie, and your vote choice. No data that directly identifies you is requested.
>
> **Why?** So that only one vote is counted per browser and to display the results (legitimate interest, GDPR art. 6.1.f).
>
> **How long?** The cookie is deleted when the browser closes. Votes are kept until the end of the demonstration, then deleted.
>
> **Where?** On Microsoft Azure, in the European Union (Spain). The pages also load files from Google and other CDNs, which receive your IP address.
>
> **Your rights:** access, erasure, objection, and complaint to the CNIL. Since the vote is pseudonymous, give the value of your `voter_id` cookie to exercise your rights.

## Licences

All dependencies are under permissive licences or licences compatible with use as a service, unmodified. Details in [docs/dependencies.md](../dependencies.md). Point of attention: **Redis 8** is triple-licensed (RSALv2, SSPLv1 or AGPLv3). Using it as an internal service, unmodified, is compatible. Reselling Redis itself as a managed service would not be, without care.
