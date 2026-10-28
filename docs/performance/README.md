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

### Version `v3` (result modifié, abandonnée, voir ADR-0009)

| Scénario | poll | result |
|---|---|---|
| **Déploiement de `v3` par `scripts/deploy.sh`** (nouvelle image, cas de la soutenance) | **65/65** | **65/65** |
| 2 rollouts enchaînés, essai 1 | 39/39 | 37/38 |
| 2 rollouts enchaînés, essai 2 | 42/42 | 42/42 |
| 2 rollouts enchaînés, essai 3 | 46/46 | 46/46 |
| Référence sans déploiement | 20/20 | 40/40 |

### Version d'origine (`v4`, 2026-10-18), après l'ADR-0009

Les résultats `v2` et `v3` ci-dessus portaient sur un result **modifié**. Modifier un composant étant éliminatoire, le code d'origine a été restauré ([ADR-0009](../adr/0009-composants-d-origine-non-modifies.md)) : transport polling, affinité `ClientIP` + `externalTrafficPolicy: Local`, `preStop` de 20 s, sans arrêt propre. Mesures avec `scripts/probe.sh` :

| Scénario | poll | result |
|---|---|---|
| Juste après `az aks start` (pods `Ready`, aucun déploiement en cours) | **~80 s sans réponse** | **~80 s sans réponse** |
| Déploiement de `v4` (code d'origine) | ok | 1 échec |
| Déploiement de `v5` | 69/69 | 68/68 |
| **Rollback** vers `v4` (`TAG=v4 SKIP_BUILD=1 scripts/deploy.sh`) | 65/66 | 66/66 |

- **Coupure après le redémarrage** : les deux applications sont tombées ensemble, avant tout déploiement. Les pods étaient prêts, mais le Load Balancer n'avait pas encore fini de router vers les nœuds recréés. Il faut donc attendre que les pages répondent avant une démonstration ([README](../../README.md)).
- **Mises à jour** : 1 échec isolé par déploiement dans 2 cas sur 3. C'est le zéro erreur exigé qui n'est **pas garanti** avec le code d'origine. Pour result, la cause la plus probable est l'arrêt immédiat de Node.js sur `SIGTERM` (le code d'origine n'a pas d'arrêt propre), combiné à l'affinité. L'échec isolé de poll pendant le rollback n'est pas expliqué (gunicorn s'arrête proprement). L'amélioration possible sans toucher au code serait un Ingress avec affinité par cookie (ADR-0009, option B).

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
| Version | `v3` (result modifié), 2026-10-15. Poll, worker et Redis sont identiques à l'origine ; seule la page result a changé depuis |

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
- Le test ajoute **un votant fictif par vote** (5 157 lignes relevées dans `votes` après le test) : k6 vide les cookies à chaque itération, donc chaque vote arrive avec un nouveau `voter_id`. La table a été vidée (`TRUNCATE votes`) après le test.

### Version d'origine (`56d0fd8`, 2026-10-18)

Même scénario, sur un déploiement fait **de zéro** (namespace supprimé, puis les seules commandes du README), avec les ressources ajustées et les tags `redis:8.10.2` et `postgres:18.6` fixés :

| Mesure | `v3` (result modifié) | **Version d'origine** |
|---|---|---|
| Requêtes | 15 453 (85 req/s) | 14 793 (82 req/s), dont 4 931 votes |
| Erreurs | 0 | **0** |
| Latence p95 | 208 ms | **260 ms** (seuil 500 ms ✅), max 1,52 s |
| File Redis | 0 | 0 |
| Redémarrages | 0 | 0 |
| poll, max par pod | 85m, 88 Mi | 109m, 89 Mi, soit **35 % de la nouvelle limite** (256 Mi) |
| result, max par pod | 14–15m sur chaque pod | **2m et 33m** |

- **Charge déséquilibrée entre les pods result** : le générateur n'a qu'une IP, et l'affinité `ClientIP` l'envoie donc toujours sur le même pod. Avec de vrais visiteurs, chacun avec son IP, la charge se répartit. Mais un public derrière un même NAT (une salle, une école) irait tout entier sur un seul pod.
- La latence est un peu plus élevée qu'avec `v3` : le transport polling de Socket.IO fait plus de requêtes. Elle reste dans le seuil.
- La table `votes` a été vidée après le test (4 933 lignes de test).

### Autoscaling HPA (`73f6937`, 2026-10-28)

Même scénario, avec le HPA de l'[ADR-0012](../adr/0012-autoscaling-hpa-poll-result.md) (2 à 4 pods, cible 70 % CPU, request de poll à 100m), juste après avoir rallumé le cluster. Évolution relevée avec `kubectl get hpa -n bernstein` toutes les 15 s :

| Moment | poll (CPU / pods) | result (CPU / pods) |
|---|---|---|
| Début du test | 5 % / 2 | 5 % / 2 |
| Montée à 50 utilisateurs | 42 % / 2 | 18 % / 2 |
| 100 utilisateurs | **95 % / 2 → 3** | 30 % / 2 |
| Fin du test | 1 % / 3 | 2 % / 2 |
| ≈ 2 min après la fin | 2 % / **3 → 2** | 2 % / 2 |

| Mesure | 2026-10-18 (2 pods fixes) | HPA, 1ᵉʳ essai (cluster tout juste rallumé) | **HPA, 2ᵉ essai (20 min plus tard)** |
|---|---|---|---|
| Requêtes | 14 793 | 14 343 (79 req/s) | **16 836 (93 req/s)** |
| Erreurs | 0 | 18 (0,12 %) | **0** |
| Latence p95 | 260 ms | 535 ms (seuil 500 ms ❌), max 3,76 s | **170 ms** ✅, max 1,01 s |
| poll | 2 pods | 95 % → 3 pods | 90 % → 3 pods |

- Le HPA fonctionne dans les deux sens : montée à 3 pods sous charge, retour à 2 après la fenêtre de stabilisation de 120 s.
- result reste à 2 : il consomme peu, la cible n'est pas atteinte.
- **Les erreurs du 1ᵉʳ essai ne se reproduisent pas** : refait 20 minutes plus tard sur le même cluster, le test donne 0 erreur et un p95 de 170 ms, avec la même montée à 3 pods. Le démarrage du 3ᵉ pod n'est donc pas en cause ; l'explication la plus probable est le cluster tout juste rallumé (nœuds et pods recréés quelques minutes avant). À retenir pour la démo : rallumer le cluster **au moins 15 minutes avant**.

### Autoscaling HPA (`73f6937`, 2026-10-28)

Même scénario, avec le HPA de l'[ADR-0012](../adr/0012-autoscaling-hpa-poll-result.md) (2 à 4 pods, cible 70 % CPU, request de poll à 100m), juste après avoir rallumé le cluster. Évolution relevée avec `kubectl get hpa -n bernstein` toutes les 15 s :

| Moment | poll (CPU / pods) | result (CPU / pods) |
|---|---|---|
| Début du test | 5 % / 2 | 5 % / 2 |
| Montée à 50 utilisateurs | 42 % / 2 | 18 % / 2 |
| 100 utilisateurs | **95 % / 2 → 3** | 30 % / 2 |
| Fin du test | 1 % / 3 | 2 % / 2 |
| ≈ 2 min après la fin | 2 % / **3 → 2** | 2 % / 2 |

| Mesure | 2026-10-18 (2 pods fixes) | HPA, 1ᵉʳ essai (cluster tout juste rallumé) | **HPA, 2ᵉ essai (20 min plus tard)** |
|---|---|---|---|
| Requêtes | 14 793 | 14 343 (79 req/s) | **16 836 (93 req/s)** |
| Erreurs | 0 | 18 (0,12 %) | **0** |
| Latence p95 | 260 ms | 535 ms (seuil 500 ms ❌), max 3,76 s | **170 ms** ✅, max 1,01 s |
| poll | 2 pods | 95 % → 3 pods | 90 % → 3 pods |

- Le HPA fonctionne dans les deux sens : montée à 3 pods sous charge, retour à 2 après la fenêtre de stabilisation de 120 s.
- result reste à 2 : il consomme peu, la cible n'est pas atteinte.
- **Les erreurs du 1ᵉʳ essai ne se reproduisent pas** : refait 20 minutes plus tard sur le même cluster, le test donne 0 erreur et un p95 de 170 ms, avec la même montée à 3 pods. Le démarrage du 3ᵉ pod n'est donc pas en cause ; l'explication la plus probable est le cluster tout juste rallumé (nœuds et pods recréés quelques minutes avant). À retenir pour la démo : rallumer le cluster **au moins 15 minutes avant**.

## Limites

- **Échantillon réduit** pour les tests de mise à jour : quelques centaines de requêtes, depuis un seul client, sur quelques essais. Ces mesures montrent que les correctifs fonctionnent, elles ne prouvent pas un taux d'erreur nul.
- **Un échec résiduel** sur result quand un second déploiement démarre avant la fin du premier (1 essai sur 3). Cause non identifiée. Pistes : délai de propagation des endpoints sur AKS, `preStop` plus long.
- **La capacité maximale n'est pas connue** : le test de charge n'a pas fait atteindre sa limite au cluster. Prochaine étape : plusieurs générateurs ou un `sleep` plus court, jusqu'au premier seuil franchi.
- Le test de charge ne mesure pas les connexions Socket.IO de result (mises à jour en direct). Seul le chargement de la page est mesuré.
- Le problème n° 1 n'a été vu qu'après l'exposition publique. Un test de charge avant l'exposition l'aurait détecté plus tôt.
