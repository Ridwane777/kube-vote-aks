# ADR-0003 : Manifestes en YAML simple, PostgreSQL en StatefulSet dans AKS

- **Statut :** Accepté
- **Date :** 2026-10-15
- **Décideurs :** Ridwane

## Contexte

L'application de vote a besoin d'une base PostgreSQL 18 persistante, avec la table `votes` créée par `schema.sql`. Elle doit être redéployable par l'évaluateur depuis le dépôt sur un cluster AKS vierge (ADR-0001, ADR-0002). Il faut aussi choisir comment écrire et appliquer les manifestes Kubernetes.

Contraintes : crédits Azure for Students, et l'équipe apprend Kubernetes pendant le projet.

## Options envisagées

### Hébergement de PostgreSQL

| Option | ✅ | ❌ |
|---|---|---|
| **A. StatefulSet + PVC (disque Azure) dans AKS** | Aucun coût en plus des nœuds et du disque ; tout est dans les manifestes ; montre la gestion d'un service avec état | Sauvegardes, mises à jour et haute disponibilité à notre charge ; une seule instance |
| B. Azure Database for PostgreSQL (Flexible Server) | Sauvegardes automatiques, haute disponibilité possible, correctifs gérés | ~15–25 €/mois minimum (estimation), ressource hors du cluster à créer à part, moins de Kubernetes à démontrer |

### Format des manifestes

| Option | ✅ | ❌ |
|---|---|---|
| **A. YAML simple, fichiers numérotés dans `k8s/`** | Lisible, aucun outil en plus, `kubectl apply -f k8s/` | Valeurs répétées entre les fichiers, pas de variantes par environnement |
| B. Kustomize | Inclus dans kubectl, overlays par environnement | Un concept de plus, inutile avec un seul environnement |
| C. Helm | Templates, versions, rollback de release | Lourd pour une seule application, cache la syntaxe Kubernetes |

## Décision

- **PostgreSQL : StatefulSet à 1 réplica**, avec un `volumeClaimTemplate` (disque Azure dynamique) et un Service. Mot de passe dans le Secret `postgres-secret`, créé hors du dépôt.
- **Manifestes : YAML simple** dans `k8s/`, numérotés dans l'ordre d'application (`00-namespace.yaml`, …), tous dans le namespace `bernstein`.

## Conséquences

### ✅ Gagné

- Déploiement complet en une commande, sans ressource Azure de plus.
- Pas de coût supplémentaire pour la base.

### ❌ Perdu / risques

- **Pas de sauvegarde automatique** : la perte du disque fait perdre les votes. Correctif possible : un CronJob `pg_dump`, ou passer à l'option B.
- **Point de défaillance unique** : un seul pod PostgreSQL. Pendant son redémarrage, le worker ne peut pas écrire.
- **Disque `ReadWriteOnce`** : il est attaché à un seul nœud à la fois, et le pod met plus de temps à redémarrer s'il change de nœud.
- **Le mot de passe est fixé au premier démarrage** : changer le Secret ne modifie pas une base déjà initialisée.

## Liens

- [ADR-0001](0001-plateforme-aks-acr.md), [ADR-0002](0002-region-spain-central.md)
