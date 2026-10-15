# ADR-0006 : Redis éphémère, sans disque ni mot de passe

- **Statut :** Accepté
- **Date :** 2026-10-15
- **Décideurs :** Ridwane

## Contexte

Redis sert de file d'attente entre poll (`RPUSH votes`) et le worker (`BLPOP votes`). Le worker vide la file en continu et écrit chaque vote dans PostgreSQL, qui est la donnée de référence. Le README de l'application accepte un Redis protégé par mot de passe (`REDIS_PASSWORD`), mais ne l'exige pas.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| **A. 1 réplica, sans disque, sans mot de passe** | Simple, démarrage instantané, pas de disque à payer ni de Secret de plus | Votes en attente perdus si Redis redémarre ; tout pod du cluster peut lire et écrire la file |
| B. Persistance AOF sur un PVC (StatefulSet) | Les votes en attente survivent à un redémarrage | Disque, StatefulSet, rattachement du disque plus lent en cas de changement de nœud |
| C. Mot de passe (`requirepass`) dans un Secret | Seuls les clients qui ont le mot de passe accèdent à la file | Un Secret de plus, à injecter dans Redis, poll et le worker |
| D. Redis répliqué (Sentinel ou opérateur) | Haute disponibilité | Complexité disproportionnée pour une file de passage |

## Décision

**Option A**, `k8s/20-redis.yaml` : un Deployment à 1 réplica, image `redis:8`, avec une readinessProbe `redis-cli ping`. Le Service est de type ClusterIP, donc Redis n'est **pas exposé** hors du cluster.

## Conséquences

### ✅ Gagné

- Aucun coût de stockage, aucun Secret de plus.
- En fonctionnement normal, la file est vide en quelques millisecondes : il n'y a presque rien à perdre.

### ❌ Perdu / risques

- **Perte des votes en attente** si Redis redémarre pendant que le worker est arrêté. Mesuré : 5 votes sont restés en attente tant que le worker n'était pas déployé, puis ont tous été traités à son arrivée.
- **Pas d'authentification** : n'importe quel pod du cluster peut lire ou injecter des votes. Le risque est limité à l'intérieur du cluster.
- **Interruption pendant une mise à jour de Redis** : 1 seul réplica, et poll est retiré du Service (`/readyz` en 503) tant que Redis ne répond pas.

### Quand changer

- Ajouter l'option C (mot de passe) et une **NetworkPolicy** (seuls poll et le worker accèdent à Redis) dès que d'autres applications partagent le cluster.
- Passer à l'option B si la perte de quelques votes devient inacceptable.
