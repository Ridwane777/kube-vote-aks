# ADR-0009 : Composants d'origine non modifiés

- **Statut :** Accepté
- **Date :** 2026-10-18
- **Décideurs :** Ridwane
- **Remplace :**
  - [ADR-0005](0005-result-websocket-sans-affinite.md) en entier ;
  - [ADR-0008](0008-mises-a-jour-sans-coupure-et-ressources.md) pour ce qui concerne result uniquement : l'arrêt propre dans `server.js` et le `preStop` de 10 s.

## Contexte

Le barème de soutenance, communiqué après l'ADR-0005, contient un **critère éliminatoire** : « *Un des cinq composants (Poll, Redis, Worker, PostgreSQL, Result) ne fonctionne pas ou a été modifié par rapport à sa version originale* ».

L'ADR-0005 avait modifié deux fichiers de result :

- `views/app.js` : transport WebSocket, calcul des pourcentages ;
- `server.js` : arrêt propre.

Une comparaison avec l'archive d'origine (`project-applications.zip`) a confirmé que **ces deux fichiers étaient les seuls modifiés**.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| **A. Code d'origine + affinité `ClientIP` et `externalTrafficPolicy: Local`** | Aucun composant modifié ; rien à installer ; configuration déjà mesurée (ADR-0004) | Fragilité mesurée pendant des rollouts enchaînés ; affinité grossière derrière un NAT |
| B. Code d'origine + Ingress avec affinité par cookie | Affinité fiable, une seule IP | Contrôleur à installer (étape de plus pour le correcteur), à mesurer de nouveau |
| C. Code d'origine + 1 seul réplica result | Plus besoin d'affinité | Plus de redondance, 2 pods coexistent pendant une mise à jour |
| D. Garder les modifications | Plus robuste | **Éliminatoire** |

## Décision

- **Option A.** `project-applications/` est remis à l'identique de l'archive d'origine, vérifié avec `diff -rq`.
- `k8s/50-result.yaml` retrouve `sessionAffinity: ClientIP` et `externalTrafficPolicy: Local`, avec un `preStop` de 20 s et `terminationGracePeriodSeconds: 40`.
- La surcharge de la commande gunicorn de poll est conservée : c'est de la **configuration de déploiement** dans le manifeste, l'image et le code restent ceux d'origine. C'est une décision de l'équipe, à défendre en soutenance.

## Conséquences

### ✅ Gagné

- Critère éliminatoire respecté : les 5 composants sont d'origine.

### ❌ Perdu / risques

- **Le bug d'affichage revient** : « -1 % » possible dans result (par exemple avec 1, 4, 1 et 0 votes). C'est un défaut du code fourni, à signaler, pas à corriger.
- **Retour de la fragilité de l'affinité** pendant les rollouts de result (voir [docs/performance](../performance/README.md)).
- **Plus d'arrêt propre** de Node.js sur `SIGTERM` : seul le `preStop` protège les requêtes en cours.
- **Doublons de gestionnaires `scores`** à chaque reconnexion Socket.IO : défaut du code d'origine, sans effet visible sur l'affichage.
- **Risque d'interprétation** sur la commande gunicorn de poll : si le jury la considère comme une modification, il faudra revenir à la commande de l'image, et le crash sous connexions inactives reviendra ([docs/performance](../performance/README.md), problème n° 1).
