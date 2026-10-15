# Architecture Decision Records

Une décision par fichier, au format MADR. Un ADR accepté n'est jamais réécrit : si une décision change, un nouvel ADR la remplace et l'ancien passe au statut « Remplacé par ADR-xxxx ».

| N° | Décision | Statut | Date |
|---|---|---|---|
| [0001](0001-plateforme-aks-acr.md) | Plateforme : AKS + ACR, 2 nœuds `B2als_v2` | Accepté (région remplacée par 0002) | 2026-10-15 |
| [0002](0002-region-spain-central.md) | Région Spain Central, resource group `bernstein-spain-rg` | Accepté | 2026-10-15 |
| [0003](0003-manifestes-yaml-postgres-statefulset.md) | Manifestes en YAML simple, PostgreSQL en StatefulSet dans AKS | Accepté | 2026-10-15 |
| [0004](0004-exposition-loadbalancer.md) | Exposition de poll et result par 2 Services `LoadBalancer` | Accepté (Service result remplacé par 0005) | 2026-10-15 |
| [0005](0005-result-websocket-sans-affinite.md) | result en WebSocket, sans affinité de session | Accepté | 2026-10-15 |
