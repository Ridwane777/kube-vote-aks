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

## Test de charge

### Méthode

| Élément | Valeur |
|---|---|
| Outil | [k6](https://k6.io), image Docker `grafana/k6`, script [`scripts/load-test.js`](../../scripts/load-test.js) |
| Scénario | Chaque utilisateur virtuel charge la page de vote, vote (choix aléatoire), charge la page des résultats, puis attend 1 s |
| Charge | Montée de 10 à 50 puis à **100 utilisateurs simultanés**, sur 3 min |
| Seuils | Moins de 1 % d'erreurs, 95 % des requêtes sous 500 ms |
| Générateur | Une machine en France (12 cœurs), vers les IP publiques en Spain Central |
| Suivi | `kubectl top` et longueur de la file Redis toutes les 30 s ; redémarrages des pods avant et après |
| Version | `v3`, 2026-10-15 |

```sh
POLL=http://<ip> RESULT=http://<ip> \
docker run --rm -i -e POLL -e RESULT grafana/k6 run - < scripts/load-test.js
```

### Résultats

| Mesure | Valeur |
|---|---|
| Requêtes | 15 453 (85 req/s), dont 5 151 votes (≈ 28 votes/s) |
| Erreurs | **0** (seuil < 1 % ✅) |
| Latence | médiane 174 ms, p95 **208 ms** (seuil < 500 ms ✅), max 6,45 s (un seul cas isolé) |
| File Redis | **0** à chaque relevé : le worker traite les votes au rythme où ils arrivent |
| Redémarrages de pods | 0 |

La latence minimale est de 145 ms. Elle vient surtout du trajet réseau entre la France et l'Espagne, pas du traitement.

Consommation maximale relevée, pendant le palier à 100 utilisateurs :

| Pod | CPU | Mémoire | Comparé à la configuration |
|---|---|---|---|
| poll (×2) | 66–85m | 85–88 Mi | CPU au-dessus de la demande (50m), sans limite donc sans ralentissement. Mémoire à **69 % de la limite** (128 Mi) |
| result (×2) | 14–15m | 36 Mi | Large marge |
| worker | 15m | 58 Mi | Très en dessous de la demande (256 Mi) : surdimensionné |
| redis | 21m | 7 Mi | — |
| postgres | 10m | 42 Mi | Pas de `requests` définis |
| Nœuds | 11–16 % CPU | 56–59 % mémoire | La mémoire est surtout occupée par les composants système d'AKS |

### Ce qu'on en conclut

- À 100 utilisateurs simultanés, l'application tient les seuils **sans erreur**, et **la limite n'a pas été atteinte**. Le facteur limitant de ce test est le générateur (1 itération par seconde et par utilisateur), pas le cluster.
- **À ajuster** :
  - limite mémoire de poll : 88 Mi sur 128 Mi, il faut la relever avant une charge plus forte, sinon risque d'`OOMKilled` ;
  - demande mémoire du worker : la réduire, par exemple à 128 Mi ;
  - `requests` de PostgreSQL : à définir.
- Le test ajoute ≈ 100 votants fictifs (un cookie `voter_id` par utilisateur virtuel) dans la table `votes`. Ils faussent les résultats affichés.

## Limites

- **Échantillon réduit** pour les tests de mise à jour : quelques centaines de requêtes, depuis un seul client, sur quelques essais. Ces mesures montrent que les correctifs fonctionnent, elles ne prouvent pas un taux d'erreur nul.
- **Un échec résiduel** sur result quand un second déploiement démarre avant la fin du premier (1 essai sur 3). Cause non identifiée. Pistes : délai de propagation des endpoints sur AKS, `preStop` plus long.
- **La capacité maximale n'est pas connue** : le test de charge n'a pas fait atteindre sa limite au cluster. Prochaine étape : plusieurs générateurs ou un `sleep` plus court, jusqu'au premier seuil franchi.
- Le test de charge ne mesure pas les connexions WebSocket de result (mises à jour en direct). Seul le chargement de la page est mesuré.
- Le problème n° 1 n'a été vu qu'après l'exposition publique. Un test de charge avant l'exposition l'aurait détecté plus tôt.
