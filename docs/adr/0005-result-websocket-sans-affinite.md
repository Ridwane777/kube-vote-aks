# ADR-0005 : result en WebSocket, sans affinité de session

- **Statut :** Accepté
- **Date :** 2026-10-15
- **Décideurs :** Ridwane
- **Remplace :** [ADR-0004](0004-exposition-loadbalancer.md), pour la configuration du Service `result` uniquement (`sessionAffinity: ClientIP` et `externalTrafficPolicy: Local`). L'exposition par 2 Services `LoadBalancer` reste valable.

## Contexte

L'ADR-0004 gardait le transport Socket.IO d'origine (polling HTTP) et compensait avec une affinité `ClientIP` et une politique `Local`. Les mesures de mise à jour sans coupure (boucle `curl` sur l'IP publique) ont montré que ce montage était fragile pendant les rollouts de result :

| Test (2026-10-15) | Échecs result |
|---|---|
| Rollout avec `preStop` de 10 s | 1 |
| 2 rollouts enchaînés, `preStop` de 20 s | ~3 min de coupure (58 échecs sur 61), non reproduite ensuite |
| 1 rollout, instrumenté | 0 sur 70 |
| 2 rollouts enchaînés, instrumenté | 1 sur 81 |

Hypothèse retenue, non prouvée : l'affinité colle un client à un pod précis, qui peut encore recevoir son trafic pendant qu'il s'arrête. La politique `Local` ajoute une dépendance à la sonde de santé du Load Balancer Azure.

En parallèle, l'affichage des pourcentages de result pouvait être négatif (« -1 % » avec 1, 4, 1 et 0 votes). Chaque part était arrondie, et la dernière était calculée par soustraction.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| A. Garder le polling, régler l'affinité | Code d'origine intact | Fragilité mesurée, affinité grossière derrière un NAT |
| B. Ingress avec affinité par cookie | Affinité fiable, une seule IP | Contrôleur à installer, toujours dépendant d'un pod précis |
| **C. Transport WebSocket uniquement** | Une seule connexion longue par client : plus besoin d'affinité ni de `Local`, répartition normale. Reconnexion automatique de Socket.IO vers un autre pod | Modifie le code fourni. Les clients dont le réseau bloque WebSocket ne peuvent plus se connecter (pas de repli en polling) |

## Décision

**Option C**, livrée en tant que `result:v2` :

- `views/app.js` : `transports:['websocket']`. Le gestionnaire `scores` n'est plus enregistré qu'une fois, car le serveur renvoie `message` à chaque reconnexion et chacune ajoutait sinon un gestionnaire en double.
- `views/app.js` : les pourcentages utilisent la méthode du plus fort reste. La somme vaut toujours 100 et aucune part n'est négative (1, 4, 1, 0 → 17, 67, 16, 0).
- `k8s/50-result.yaml` : suppression de `sessionAffinity` et `externalTrafficPolicy`. On garde un `preStop` de 10 s et la répartition des pods sur les nœuds.

## Vérification (2026-10-15, déploiement de `v2` par `scripts/deploy.sh`)

- Handshake WebSocket sur l'IP publique : `101 Switching Protocols`. Le Service est en `affinity=None`, `policy=Cluster`.
- Les 2 pods result sont sur 2 nœuds différents.
- Boucle `curl` pendant le déploiement de `v2`, puis pendant 2 rollouts enchaînés : poll 88/88, **result 86/88**. Les 2 échecs (timeouts de 2 s, à 3 s d'intervalle) ont eu lieu pendant les rollouts enchaînés. Le **zéro erreur n'est pas encore démontré pour result**.

## Conséquences

### ✅ Gagné

- Plus d'affinité : le trafic se répartit normalement et un pod peut disparaître sans casser les sessions des autres.
- Plus de dépendance à `externalTrafficPolicy: Local` ni à la sonde par nœud du Load Balancer.
- Affichage correct des pourcentages.

### ❌ Perdu / risques

- **Code fourni modifié** : à justifier en soutenance, et à refaire si une nouvelle version de l'application est fournie.
- **Pas de repli en polling** pour les réseaux qui bloquent WebSocket.
- **Coupure WebSocket à chaque rollout** : les navigateurs ouverts se reconnectent (environ 1 s), sans erreur visible.
- **Échecs résiduels pendant des rollouts enchaînés**, cause non identifiée. Pistes : arrêt immédiat de Node.js sur `SIGTERM` (pas d'arrêt gracieux dans `server.js`), délai de propagation des endpoints sur AKS.

## Liens

- [ADR-0004](0004-exposition-loadbalancer.md)
- Code : `project-applications/poll-application/result/views/app.js` ; manifeste : `k8s/50-result.yaml`
