# ADR-0011 : Déploiement déclenché depuis Jenkins

- **Statut :** Accepté, configuré et testé le 2026-10-20 (build `80cb6c5` réussi)
- **Date :** 2026-10-20
- **Décideurs :** Ridwane
- **Complète :** [ADR-0010](0010-deploiement-github-actions.md). Le workflow GitHub Actions est conservé et redevient utilisable dès que l'organisation dispose de nouveau de minutes.

## Contexte

L'[ADR-0010](0010-deploiement-github-actions.md) a ajouté un déploiement depuis un lien avec GitHub Actions. Les **minutes GitHub Actions de l'organisation sont épuisées** : les workflows ne tournent plus sur les machines de GitHub. Un membre de l'équipe dispose déjà d'un **serveur Jenkins sur un VPS**.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| **A. Jenkins existant sur le VPS** | Aucun serveur à créer ni à payer ; lien « Build with Parameters » ; `Jenkinsfile` versionné dans le dépôt | Un **secret** (mot de passe du service principal) stocké dans Jenkins ; l'interface Jenkins est exposée sur Internet ; dépend du VPS d'un membre |
| B. Runner GitHub Actions auto-hébergé | Même workflow, sans minutes consommées, OIDC sans secret | Il faut les **droits d'administration** du dépôt pour enregistrer le runner, et l'équipe ne les a pas |
| C. Attendre la remise à zéro mensuelle des minutes | Rien à faire | Date incertaine, minutes partagées avec les autres groupes |
| D. Jenkins sur une nouvelle VM Azure | Indépendant des machines des membres | ≈ 1 €/jour de plus, et le dernier quota de vCPU disponible |

## Décision

**Option A**, `Jenkinsfile` à la racine :

- **rien n'est installé dans Jenkins** : les étapes s'exécutent dans une image d'outils versionnée, `ci/Dockerfile` (`az`, `kubectl`, `envsubst`, `git`), lancée par le plugin *Docker Pipeline* avec le socket Docker de l'hôte. Le Jenkins existant (`jenkins/jenkins:lts`, socket et binaire Docker déjà montés, plugin déjà installé) n'est pas modifié ;
- paramètres `TAG` (vide = commit actuel) et `ROLLBACK` (redéploiement sans reconstruction, `SKIP_BUILD=1`), le tag étant validé avant usage ;
- connexion à Azure par un **service principal** avec le rôle *Contributor* limité au groupe `bernstein-spain-rg`. Son mot de passe est dans les *Credentials* de Jenkins (`azure-deploy-sp`), masqué dans les journaux, **jamais dans le dépôt** ;
- l'état Azure et kubectl de chaque build est isolé dans un dossier temporaire, puis supprimé à la fin (`az logout`) ;
- cluster rallumé s'il est arrêté, et `POSTGRES_PASSWORD` généré pendant le build, comme dans l'ADR-0010 ;
- `disableConcurrentBuilds` empêche deux déploiements simultanés.

## Conséquences

### ✅ Gagné

- Déploiement et rollback depuis un lien, malgré l'épuisement des minutes GitHub Actions.
- Même logique de déploiement (`scripts/deploy.sh`) en ligne de commande, avec GitHub Actions et avec Jenkins.
- Aucun secret dans le dépôt.

### ❌ Perdu / risques

- **Un secret de plus à protéger** : le mot de passe du service principal. Il expire (1 an par défaut) et doit être renouvelé (`az ad sp credential reset`). S'il fuit, l'accès au groupe de ressources est ouvert jusqu'à sa révocation.
- **Surface d'attaque** : un Jenkins exposé sur Internet doit être tenu à jour (Jenkins et plugins) et réservé aux membres du groupe.
- **Dépendance au VPS d'un membre** : s'il est éteint ou indisponible, le lien ne marche plus. La procédure en ligne de commande reste la référence.
- Le VPS doit avoir Docker et assez de mémoire pour construire l'image Java du worker (Maven).
