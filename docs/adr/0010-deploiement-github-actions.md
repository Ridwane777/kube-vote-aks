# ADR-0010 : Déploiement déclenché depuis GitHub Actions

- **Statut :** Accepté, configuration Azure en attente (étape 12.1 du guide)
- **Date :** 2026-10-20
- **Décideurs :** Ridwane

## Contexte

On nous a demandé s'il était possible de lancer le déploiement **depuis un lien**. Jusqu'ici, le déploiement se fait uniquement par `scripts/deploy.sh`, depuis la machine d'un membre qui a `az`, `docker` et `kubectl`. Contraintes :

- aucun secret dans le dépôt, historique compris (critère éliminatoire) ;
- les membres ont les droits d'écriture sur le dépôt GitHub, **pas d'administration** : ils ne peuvent pas créer de secrets GitHub ;
- la procédure manuelle du guide doit rester valable.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| **A. GitHub Actions, déclenchement manuel (`workflow_dispatch`) + identité fédérée OIDC** | Un lien et un bouton ; aucun secret stocké ; réutilise `scripts/deploy.sh` ; chaque déploiement tracé (qui, quand, quel commit) | Configuration Azure à faire une fois par le propriétaire de l'abonnement ; dépend de GitHub Actions |
| B. GitHub Actions avec un *service principal* et son mot de passe dans un secret GitHub | Configuration classique | Un secret à créer (droits d'administration nécessaires) et à faire tourner ; risque de fuite |
| C. Déploiement automatique à chaque push sur `main` | Aucun clic | Déploie sans le vouloir, consomme des builds et du crédit ; incompatible avec une démonstration maîtrisée |
| D. Azure DevOps Pipelines | Intégré à Azure | Un outil et un compte de plus, le code est sur GitHub |

## Décision

**Option A**, `.github/workflows/deploy.yml` :

- déclenchement **manuel** uniquement, avec deux champs : `tag` (vide = commit actuel) et `rollback` (redéploiement sans reconstruction, `SKIP_BUILD=1`) ;
- connexion à Azure par **OIDC** : l'identité n'est acceptée que pour `repo:Ridwane777/bernstein:ref:refs/heads/main`, avec le rôle *Contributor* limité au groupe `bernstein-spain-rg` ;
- le cluster est rallumé s'il est arrêté ;
- `POSTGRES_PASSWORD` est **généré pendant le run**. Le script ne l'utilise que si le Secret Kubernetes n'existe pas encore, il n'est donc jamais stocké ailleurs que dans Kubernetes ;
- `concurrency` empêche deux déploiements simultanés ;
- le champ `tag` est validé avant usage (caractères autorisés dans un tag d'image) et passé par variable d'environnement, jamais injecté dans le script.

## Conséquences

### ✅ Gagné

- Déploiement et rollback depuis un navigateur, sans outil installé.
- Aucun secret créé ni stocké : les identifiants dans le workflow (client, tenant, abonnement) ne sont pas des secrets.
- Une seule logique de déploiement (`scripts/deploy.sh`), pour la ligne de commande comme pour le lien.

### ❌ Perdu / risques

- **Configuration Azure manuelle** (étape 12.1) : elle demande de créer une identité et de lui donner un rôle. Ce n'est pas automatisable sans droits plus élevés.
- **Toute personne qui peut écrire sur le dépôt peut déployer** et allumer le cluster, donc consommer du crédit.
- **Le mot de passe généré par un run pourrait diverger** s'il était utilisé pour réinitialiser une base existante. Ce n'est pas le cas : il ne sert qu'à créer le Secret absent.
- **Builds plus lents** qu'en local : les machines GitHub n'ont pas de cache Docker entre deux runs.
- Dépendance supplémentaire à GitHub Actions, dont l'activation pour l'organisation n'a pas pu être vérifiée faute de droits d'administration.
