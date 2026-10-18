# Business plan

Le projet Bernstein est un projet pédagogique. Ce document examine ce que deviendrait le travail réalisé s'il était proposé comme un service. Les chiffres de coûts viennent de [docs/costs](../costs/README.md) et ceux de capacité de [docs/performance](../performance/README.md). Les hypothèses de marché ne sont pas vérifiées et sont marquées comme telles.

## Problème

Un organisateur d'événement (conférence, cours, réunion d'entreprise, association) veut **sonder son public en direct** et afficher les résultats à l'écran en temps réel. Les outils existants sont des services hébergés par des tiers, souvent hors de l'Union européenne, avec des formules payantes par organisateur.

## Solution

Une application de vote en direct (pages de vote et de résultats en temps réel), **déployable en une commande** sur le cluster Kubernetes du client ou sur un cluster géré par nous :

- mises à jour progressives, mesurées : 0 à 1 requête en échec par déploiement avec le code d'origine ([docs/performance](../performance/README.md)) ;
- hébergement dans l'UE (Espagne) ;
- aucun compte demandé aux votants, seul un identifiant pseudonyme est utilisé.

## Marché et clients cibles (hypothèses)

| Segment | Besoin | Sensibilité |
|---|---|---|
| Écoles et universités | Sondages en cours | Prix, données des étudiants (RGPD) |
| Entreprises (réunions internes) | Hébergement dans l'UE, voire sur leur propre infrastructure | Souveraineté des données |
| Associations et collectivités | Consultations simples | Prix |

## Concurrence

| Concurrent | Forces | Notre différence |
|---|---|---|
| Slido, Mentimeter, Wooclap, Kahoot | Produits complets (quiz, nuages de mots, intégrations PowerPoint et Teams), notoriété | Déploiement sur l'infrastructure du client ou dans l'UE, code source maîtrisé, coût d'infrastructure connu |
| Formulaires (Google Forms, Microsoft Forms) | Gratuits, connus | Résultats en direct à l'écran |

Notre produit est beaucoup moins riche fonctionnellement : 4 choix fixes, une seule question.

## Modèle économique (hypothèse)

| Offre | Contenu | Prix indicatif |
|---|---|---|
| Auto-hébergée | Manifestes, scripts, documentation, support par e-mail | Licence annuelle par organisation |
| Gérée par événement | Cluster dédié le temps de l'événement | Forfait par événement |
| Gérée à l'année | Cluster partagé, plusieurs sondages | Abonnement mensuel |

### Coût unitaire (mesuré et estimé)

| Élément | Valeur | Source |
|---|---|---|
| Coût du cluster allumé | ≈ 4,3 €/jour | Estimé, prix Azure publics |
| Capacité démontrée | 100 utilisateurs simultanés, ≈ 28 votes/s, 0 erreur, p95 208 ms, cluster à 16 % de CPU au plus | Mesuré (k6) |
| Événement d'une journée (cluster allumé 24 h, arrêté le reste du temps) | ≈ 4,3 € d'infrastructure, plus ≈ 1 €/jour de coûts fixes (IP, ACR) | Estimé |

La capacité maximale n'est pas connue : le test de charge n'a pas atteint la limite du cluster. À 100 votants, le coût d'infrastructure est d'environ **4 centimes par votant et par jour**, et il baisse à mesure que le public grandit, puisque le cluster n'est pas saturé.

## SWOT

| | Positif | Négatif |
|---|---|---|
| **Interne** | **Forces** : déploiement reproductible en une commande ; mises à jour progressives et rollback mesurés ; hébergement UE ; coûts connus et maîtrisés | **Faiblesses** : fonctionnalités minimales ; zéro erreur non garanti pendant les mises à jour de result (code imposé) ; pas de HTTPS ; pas de sauvegarde ; bibliothèques front obsolètes ([docs/legal](../legal/README.md)) ; une seule personne sait l'exploiter |
| **Externe** | **Opportunités** : demande de souveraineté des données (RGPD, secteur public) ; organisations déjà équipées de Kubernetes | **Menaces** : concurrents établis et gratuits pour un petit usage ; dépendance à Azure et à ses quotas ; évolution des licences (Redis) |

## Feuille de route

| Étape | Contenu | Prérequis technique |
|---|---|---|
| 1. Fiabiliser | HTTPS, sauvegardes, supervision, tags fixés | [Rétrospective](../retrospective/README.md), actions 3 à 6 |
| 2. Produit minimal vendable | Questions et choix configurables (`OPTION_A` à `OPTION_D` existent déjà), plusieurs sondages | Modifications de poll et result |
| 3. Industrialiser | CI/CD, Kustomize, un namespace par client | ADR à écrire |
| 4. Passer à l'échelle | Autoscaling (HPA, puis autoscaler de nœuds), mesure de la capacité maximale | Test de charge jusqu'à la saturation |
