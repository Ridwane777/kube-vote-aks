# ADR-0007 : Un seul réplica pour le worker

- **Statut :** Accepté
- **Date :** 2026-10-15
- **Décideurs :** Ridwane

## Contexte

Le worker lit la file Redis (`BLPOP`) et écrit chaque vote dans PostgreSQL par UPSERT : une ligne par votant, et le dernier vote du votant l'emporte. Il ne reçoit aucune connexion, il n'a donc pas de Service (voir `docs/kubernetes-guide.md`, § 7). Il expose seulement `/healthz` et `/readyz` sur le port 80 pour les sondes.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| **A. 1 réplica** | L'ordre des votes d'un même votant est conservé | Pas de traitement en parallèle ; la file s'accumule pendant un redémarrage |
| B. N réplicas | Débit multiplié, tolère la perte d'un pod | `BLPOP` distribue les votes entre les workers : deux votes successifs d'un même votant peuvent être écrits dans le désordre, et l'ancien vote peut écraser le nouveau |
| C. N réplicas avec partitionnement par votant | Débit et ordre conservés | Modification du code (plusieurs files, hachage du votant) |

## Décision

**Option A**, `k8s/40-worker.yaml` :

- 1 réplica ;
- `maxSurge: 1` et `maxUnavailable: 0` : pendant une mise à jour, le nouveau worker démarre avant que l'ancien s'arrête ;
- `startupProbe` qui laisse jusqu'à 2 minutes à la JVM pour démarrer ;
- mot de passe PostgreSQL lu dans le Secret `postgres-secret`.

## Conséquences

### ✅ Gagné

- Résultats corrects : le dernier vote d'un votant est toujours celui qui compte.
- Les votes ne sont pas perdus quand le worker est absent : ils attendent dans Redis (5 votes en attente, tous traités au démarrage).

### ❌ Perdu / risques

- **Débit limité à un processus.** Il n'a pas été mesuré : il n'y a pas encore de test de charge (voir [docs/performance](../performance/README.md)).
- **Pendant une mise à jour, deux workers coexistent quelques secondes** (`maxSurge: 1`). L'ordre n'est alors pas strictement garanti. L'impact est négligeable : il faudrait qu'un même votant vote deux fois dans cette fenêtre.
- Si le pod tombe, l'affichage des résultats prend du retard jusqu'à son redémarrage. Aucun vote n'est perdu.

### Quand changer

Si la file Redis grossit de façon durable sous la charge, passer à l'option C.
