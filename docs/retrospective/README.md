# Rétrospective

Un regard sur **l'ensemble du projet**, du bootstrap au déploiement mesuré : ce qu'on garderait, ce qu'on aurait pu faire mieux pour réduire les coûts, le temps et les risques, et les actions suivantes.

## Ce qu'on garderait

- **Les mesures avant de conclure.** Le zéro downtime a été vérifié avec une boucle `curl`, la capacité avec k6. Sans ces mesures, deux défauts graves seraient passés inaperçus : poll qui redémarrait en boucle, et une coupure de 3 minutes sur result.
- **Les ADR écrits au moment de la décision**, remplacés plutôt que réécrits (0004 → 0005). L'historique montre ce qu'on a appris.
- **Les tags d'image immuables** et le script unique `scripts/deploy.sh` : un déploiement est reproductible et traçable.
- **Les Secrets hors du dépôt**, l'identité managée pour l'ACR : aucun identifiant dans git.
- **Un service managé (AKS)** plutôt qu'un cluster monté à la main : aucune heure passée sur etcd ou les certificats.

## Ce qu'on aurait pu faire mieux

| Constat | Conséquence | Alternative concrète | Quand elle devient préférable | Son coût |
|---|---|---|---|---|
| Plateforme choisie **avant** de vérifier les politiques de régions, les tailles autorisées et les quotas | 4 régions essayées, un cluster à moitié créé, un resource group supprimé ([ADR-0002](../adr/0002-region-spain-central.md)) | Vérifier d'abord : `az policy assignment list`, `az vm list-skus`, `az vm list-usage` | Toujours, sur un abonnement restreint (étudiant, entreprise) | 15 min |
| **Disque OS par défaut** (Premium 128 Go) | 1,26 €/jour, 30 % de la facture ([docs/costs](../costs/README.md)) | `--node-osdisk-size 30` à la création du cluster | Dès qu'on paie le cluster soi-même | Aucun à la création. Recréer le pool de nœuds ensuite |
| **VM pour le bootstrap** (Minikube) | 12,54 € et du temps de dépannage (VM de 892 Mo, redimensionnement) | `kind` ou Minikube en local, ou le cluster AKS directement | Si la machine locale a ≥ 8 Go de RAM | 0 € |
| **Test de charge après l'exposition**, pas avant | Le défaut de gunicorn (1 worker *sync*) n'a été vu que lorsqu'un utilisateur l'a subi | Lancer `scripts/load-test.js` avant toute exposition | Toujours, avant une mise en ligne | 5 min par test |
| **Barème lu après coup** : result modifié (WebSocket, arrêt propre) alors que modifier un composant est éliminatoire | Deux ADR (0005 puis 0009) et un retour au code d'origine avec sa fragilité d'affinité | Lire **tout** le barème avant les choix d'architecture. Dans ces contraintes, l'affinité par cookie d'un Ingress est la seule amélioration possible sans toucher au code | Dès qu'un composant est imposé tel quel | Installer et maintenir un contrôleur Ingress |
| **`envsubst` sur du YAML simple** | `kubectl apply -f k8s/` ne marche plus seul, et le registre et le tag sont gérés par un script maison | **Kustomize** (`kustomize edit set image`), inclus dans kubectl | Dès qu'il faut paramétrer une image ou un registre | Un fichier `kustomization.yaml`. Changer l'ADR-0003 |
| **Déploiement manuel** depuis le poste d'un développeur | Dépend de la machine et des outils installés localement | **CI/CD** (GitHub Actions) : build, push et déploiement à chaque commit sur `main`, avec identité fédérée Azure (OIDC) | Dès qu'il y a plus d'un développeur ou plus d'un déploiement par semaine | ≈ 1 jour de mise en place |
| **Tags flottants** `redis:8`, `postgres:18` | Une nouvelle version peut arriver sans qu'on l'ait choisie (Redis 8.10.2 relevé) | Tags précis ou empreintes `@sha256` | Toujours en production | Mettre à jour les tags à la main |
| **Pas de supervision** | Les incidents ont été vus par un utilisateur ou par nos tests, jamais par une alerte | Prometheus + Grafana (kube-prometheus-stack) ou Azure Monitor (payant) | Dès que l'application doit tourner sans surveillance humaine | CPU et mémoire dans le cluster, ou ≈ 2 €/Go ingéré avec Azure Monitor |
| **Pas de sauvegarde** de PostgreSQL | Perte des votes si le disque est perdu ([ADR-0003](../adr/0003-manifestes-yaml-postgres-statefulset.md)) | CronJob `pg_dump` vers un Azure Blob, ou Azure Database for PostgreSQL | Dès que les votes ont de la valeur | Quelques centimes par mois en Blob, ≈ 15–25 €/mois pour la base managée |
| **Pas de HTTPS** | Votes et cookie en clair ([docs/legal](../legal/README.md)) | Ingress + cert-manager + nom de domaine | Avant toute utilisation réelle | Un nom de domaine (≈ 10 €/an) et un contrôleur à maintenir |

## Ce qui aurait réduit…

- **…les coûts :**
  - disque OS de 30 Go ;
  - bootstrap en local ;
  - arrêt du cluster entre les séances (≈ 3,3 €/jour économisés) ;
  - une seule IP publique avec un Ingress.
- **…le temps :**
  - vérifier les contraintes Azure avant d'écrire l'ADR de plateforme ;
  - lire le code des applications (transport Socket.IO, serveur gunicorn) avant de choisir l'exposition ;
  - un test de charge dès le premier déploiement.
- **…les risques :**
  - HTTPS ;
  - sauvegardes ;
  - tags d'images fixés ;
  - supervision avec alertes ;
  - PodDisruptionBudget.

## Actions suivantes

| Priorité | Action | Document lié |
|---|---|---|
| 1 | Relever le coût mesuré d'AKS dans Cost Management | [docs/costs](../costs/README.md) |
| ✅ | Ressources ajustées : limite mémoire de poll 256 Mi, demande du worker 128 Mi, `requests` de PostgreSQL et Redis (2026-10-18) | [docs/performance](../performance/README.md) |
| ✅ | Tags fixés : `redis:8.10.2`, `postgres:18.6` (2026-10-18) | [docs/dependencies.md](../dependencies.md) |
| ✅ | PodDisruptionBudgets sur poll et result, `k8s/60-disruption-budgets.yaml` (2026-10-18) | [ADR-0008](../adr/0008-mises-a-jour-sans-coupure-et-ressources.md) |
| ✅ | Déploiement depuis un lien : Jenkins (testé), GitHub Actions prêt mais minutes épuisées (2026-10-20) | [ADR-0010](../adr/0010-deploiement-github-actions.md), [ADR-0011](../adr/0011-deploiement-jenkins.md) |
| 5 | Passer à Kustomize | ADR à écrire |
| 6 | Mettre en place HTTPS et la sauvegarde de PostgreSQL avant toute utilisation réelle | [docs/legal](../legal/README.md) |
