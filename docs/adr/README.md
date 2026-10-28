# Architecture Decision Records

Une décision par fichier, au format MADR. Un ADR accepté n'est jamais réécrit : si une décision change, un nouvel ADR la remplace et l'ancien passe au statut « Remplacé par ADR-xxxx ».

| N° | Décision | Statut | Date |
|---|---|---|---|
| [0001](0001-plateforme-aks-acr.md) | Plateforme : AKS + ACR, 2 nœuds `B2als_v2` | Accepté (région remplacée par 0002) | 2026-10-15 |
| [0002](0002-region-spain-central.md) | Région Spain Central, resource group `bernstein-spain-rg` | Accepté | 2026-10-15 |
| [0003](0003-manifestes-yaml-postgres-statefulset.md) | Manifestes en YAML simple, PostgreSQL en StatefulSet dans AKS | Accepté | 2026-10-15 |
| [0004](0004-exposition-loadbalancer.md) | Exposition de poll et result par 2 Services `LoadBalancer` | Accepté (Service result remplacé par 0005) | 2026-10-15 |
| [0005](0005-result-websocket-sans-affinite.md) | result en WebSocket, sans affinité de session | Remplacé par 0009 | 2026-10-15 |
| [0006](0006-redis-ephemere-sans-mot-de-passe.md) | Redis éphémère, sans disque ni mot de passe | Accepté | 2026-10-15 |
| [0007](0007-worker-un-replica.md) | Un seul réplica pour le worker | Accepté | 2026-10-15 |
| [0008](0008-mises-a-jour-sans-coupure-et-ressources.md) | Mises à jour sans coupure, sondes et ressources | Accepté (partie result remplacée par 0009, HPA ajouté par 0012) | 2026-10-15 |
| [0009](0009-composants-d-origine-non-modifies.md) | Composants d'origine non modifiés, affinité `ClientIP` rétablie pour result | Accepté | 2026-10-18 |
| [0010](0010-deploiement-github-actions.md) | Déploiement déclenché depuis GitHub Actions (OIDC, sans secret) | Accepté, configuration Azure en attente | 2026-10-20 |
| [0011](0011-deploiement-jenkins.md) | Déploiement déclenché depuis Jenkins (minutes GitHub Actions épuisées) | Accepté, testé (build `80cb6c5`) | 2026-10-20 |
| [0012](0012-autoscaling-hpa-poll-result.md) | Autoscaling HPA de poll et result, de 2 à 4 pods (70 % CPU) | Accepté, testé | 2026-10-28 |
| [0012](0012-autoscaling-hpa-poll-result.md) | Autoscaling HPA de poll et result, de 2 à 4 pods (70 % CPU) | Accepté, testé | 2026-10-28 |
