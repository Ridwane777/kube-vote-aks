# Performance : mise à jour sans coupure

Le sujet exige qu'une mise à jour soit déployée « *without any downtime* », c'est-à-dire qu'un client qui interroge l'application en continu ne reçoive aucune erreur. Ce document décrit la méthode de mesure, les problèmes trouvés, les correctifs et les résultats, **échecs compris**.

## Méthode

| Élément | Valeur |
|---|---|
| Cluster | AKS `bernstein-aks`, Kubernetes 1.35.8, 2 nœuds `Standard_B2als_v2` (2 vCPU, 4 Go), Spain Central |
| Client | Une machine (poste de l'équipe, en France), via les IP publiques des Services `LoadBalancer` |
| Outil | [`scripts/probe.sh`](../../scripts/probe.sh) : un `curl` sur `/` de poll puis de result, toutes les 0,2 s, timeout de 2 s |
| Critère | Toute réponse autre que HTTP 200 est une erreur (`000` = pas de réponse dans les 2 s) |
| Date | 2026-10-15 |

Format du journal : `heure service code` (ex. `22:52:09.344 result 000`).

### Reproduire

```sh
scripts/probe.sh /tmp/probe.log                          # terminal 1
ACR_NAME=<registre> TAG=<nouveau-tag> scripts/deploy.sh  # terminal 2
# Ctrl+C dans le terminal 1 : résumé ok / erreurs
```

Scénario plus dur, utilisé pour éprouver les correctifs : 2 rollouts enchaînés de result (`kubectl rollout restart deploy/result -n bernstein` 2 fois, en attendant la fin de chacun).

## Problèmes trouvés et correctifs

| # | Symptôme mesuré | Cause | Correctif |
|---|---|---|---|
| 1 | Dès l'exposition publique, poll redémarre en boucle (6-7 redémarrages, `CrashLoopBackOff`), CSS non chargé, page en erreur | L'image lance gunicorn avec **un seul worker *sync***. Une connexion inactive (préconnexion d'un navigateur, robot) le bloque, la `livenessProbe` dépasse 1 s et Kubernetes tue le conteneur | `command` surchargée : `--worker-class gthread --workers 2 --threads 4`. `timeoutSeconds: 2` sur les sondes. Vérifié : 3 connexions inactives ouvertes, `/healthz` répond toujours |
| 2 | 1 échec sur poll pendant un rolling update | L'ancien pod s'arrête avant que le Load Balancer et kube-proxy l'aient retiré de leur liste | `preStop` de 10 s : le pod continue de répondre pendant la propagation |
| 3 | Échecs sur result pendant les rollouts, une fois ~3 min de coupure (58 sur 61) | Hypothèse : affinité `ClientIP` + `externalTrafficPolicy: Local`, nécessaires au transport polling de Socket.IO | Passage au transport WebSocket, suppression de l'affinité ([ADR-0005](../adr/0005-result-websocket-sans-affinite.md)) |
| 4 | Encore 2 échecs sur 88 pendant 2 rollouts enchaînés | Node.js s'arrêtait net sur `SIGTERM` | Arrêt propre dans `server.js` : fin des requêtes en cours, fermeture des WebSockets et de PostgreSQL |
| — | Les 2 réplicas d'une application parfois sur le même nœud | Le scheduler ne garantit pas la répartition | `topologySpreadConstraints` (souple, `ScheduleAnyway`) |

## Résultats

### Avant les correctifs 3 et 4

| Test | poll | result |
|---|---|---|
| Rollout, `preStop` de 10 s | 20/20 | 1 échec |
| 2 rollouts, `preStop` de 20 s | — | 58 échecs / 61 |
| 1 rollout | — | 70/70 |
| 2 rollouts | — | 80/81 |
| WebSocket (`v2`), déploiement + 2 rollouts | 88/88 | 86/88 |

### Version finale (`v3`)

| Scénario | poll | result |
|---|---|---|
| **Déploiement de `v3` par `scripts/deploy.sh`** (nouvelle image, cas de la soutenance) | **65/65** | **65/65** |
| 2 rollouts enchaînés, essai 1 | 39/39 | 37/38 |
| 2 rollouts enchaînés, essai 2 | 42/42 | 42/42 |
| 2 rollouts enchaînés, essai 3 | 46/46 | 46/46 |
| Référence sans déploiement | 20/20 | 40/40 |

## Limites

- **Échantillon réduit** : quelques centaines de requêtes, depuis un seul client, sur quelques essais. Ces mesures montrent que les correctifs fonctionnent, elles ne prouvent pas un taux d'erreur nul.
- **Un échec résiduel** sur result quand un second déploiement démarre avant la fin du premier (1 essai sur 3). Cause non identifiée. Pistes : délai de propagation des endpoints sur AKS, `preStop` plus long.
- **Pas de test de charge** : la capacité (requêtes par seconde, latence sous charge, comportement à la limite des `resources`) n'est pas mesurée. Prochaine étape : un test `k6` ou `hey` sur poll, avec un seuil de latence et le suivi des redémarrages.
- Le problème n° 1 n'a été vu qu'après l'exposition publique. Un test de charge avant l'exposition l'aurait détecté plus tôt.
