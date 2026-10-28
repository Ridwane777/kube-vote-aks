# ADR-0012 : Autoscaling horizontal (HPA) de poll et result, de 2 à 4 pods

- **Statut :** Accepté, testé le 2026-10-28
- **Date :** 2026-10-28
- **Décideurs :** Ridwane, Harry
- **Complète :** [ADR-0008](0008-mises-a-jour-sans-coupure-et-ressources.md), qui prévoyait un HPA « une fois la capacité mesurée » (voir [docs/performance](../performance/README.md))

## Contexte

poll et result tournaient avec **2 réplicas fixes**. Le test de charge (100 utilisateurs virtuels) a mesuré au plus **109m de CPU par pod poll**, alors que sa request était de 50m. Les 2 nœuds `B2als_v2` restaient à 16 % de CPU : il y a de la place pour plus de pods, mais rien ne les créait automatiquement.

Le HPA calcule l'utilisation **par rapport à la request CPU**. Une request trop basse le ferait monter dès la moindre charge. metrics-server est déjà installé par AKS.

## Options envisagées

| Option | ✅ | ❌ |
|---|---|---|
| **A. HPA min 2, max 4, cible 70 % CPU** | Garde la haute disponibilité (2 pods sur 2 nœuds, PDB `minAvailable: 1`) ; tient sur les 2 nœuds (≈ 0,8 cœur demandé au maximum sur ≈ 3,8) | Ne réagit qu'au CPU |
| B. HPA min 1, max 2 | Moins de pods au repos | Un seul pod : plus de redondance, et le PDB `minAvailable: 1` **bloque le vidage des nœuds** (maintenance AKS) |
| C. Garder 2 réplicas fixes | Rien à faire | Aucune réaction à la charge |
| D. HPA + autoscaler de nœuds | Peut dépasser la taille des 2 nœuds | Quota de **6 vCPU** déjà presque atteint ; coût variable ; inutile à ce niveau de charge |
| E. KEDA (mise à l'échelle sur la file Redis) | Pertinent pour le worker | Un composant de plus à installer ; le worker reste à 1 réplica ([ADR-0007](0007-worker-un-replica.md)) |

## Décision

**Option A**, dans `k8s/70-autoscaling.yaml` (`autoscaling/v2`) :

- un HPA pour poll et un pour result : `minReplicas: 2`, `maxReplicas: 4`, `averageUtilization: 70` ;
- **redescente stabilisée sur 120 s** (`behavior.scaleDown`), pour éviter de supprimer des pods (et de couper des connexions Socket.IO de result) à chaque creux de charge ;
- **request CPU de poll : 50m → 100m**, proche de sa consommation mesurée, pour que 70 % corresponde à une vraie charge ;
- **`replicas` retiré** des Deployments poll et result : sinon chaque `kubectl apply` remettrait le nombre de pods à 2, contre la décision du HPA ;
- pas de HPA pour le worker (1 seul consommateur de la file, ADR-0007), ni pour Redis et PostgreSQL (avec état).

## Conséquences

### ✅ Gagné

- Mesuré le 2026-10-28 avec `scripts/load-test.js` : poll est passé de **2 à 3 pods** à 95 % de la request, puis revenu à 2 environ 2 minutes après la fin de la charge. result est resté à 2 (30 % au plus), comme prévu au vu de sa faible consommation.
- La haute disponibilité et les PDB restent valables, puisque le minimum reste 2.
- Aucun coût supplémentaire : on paie les nœuds, pas les pods.

### ❌ Perdu / risques

- **Migration d'un cluster existant** : retirer `replicas` d'un Deployment déjà créé par `kubectl apply` le ramène **une fois à 1 pod** avant que le HPA le remonte. On l'a évité en effaçant d'abord le champ de l'annotation `last-applied` (`kubectl apply set-last-applied`, voir le guide de déploiement). Un cluster neuf n'est pas concerné.
- **Réaction en environ 1 minute** (collecte des métriques, toutes les 15 s, plus démarrage du pod) : un pic très bref passe avant que le pod en plus soit prêt.
- **result et l'affinité `ClientIP`** : un nouveau pod ne reçoit que de nouveaux clients. À la redescente, les navigateurs branchés sur le pod supprimé se reconnectent (Socket.IO en polling). Un public derrière un même NAT reste sur un seul pod, quel que soit le nombre de pods.
- Au 1ᵉʳ test, juste après le rallumage du cluster, **18 requêtes sur 14 343 ont échoué (0,12 %)**, avec un p95 de 535 ms. Refait 20 minutes plus tard : **0 erreur sur 16 836, p95 170 ms**, même montée à 3 pods. Les erreurs viennent probablement du cluster pas encore stabilisé, pas du HPA.

### Quand changer

- Charge dépassant 4 pods poll : remonter `maxReplicas`, puis ajouter un nœud si la mémoire des nœuds dépasse 80 %.
- File Redis qui grossit : KEDA sur la longueur de la file, à condition de rendre le worker multi-réplica.
