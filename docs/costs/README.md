# Coûts

Abonnement **Azure for Students** (crédit de 100 $), compte de l'équipe. Ce document sépare le **mesuré** (relevé dans Azure) de l'**estimé** (calculé, avec sa méthode).

## Mesuré

| Poste | Montant | Source |
|---|---|---|
| VM du bootstrap (Minikube), resource group `rg-vm-pl`, supprimée | **12,54 €** | Portail Azure, Cost Management, relevé par l'équipe |
| Cluster AKS et ACR (2026-10-15, première journée) | **< 0,10 €** | Portail Azure, Cost Management, relevé par l'équipe le 2026-10-16. Le portail affiche les coûts avec un décalage de plusieurs heures : ce montant ne couvre probablement pas encore toute la journée. À relever de nouveau |

L'API de consommation (`az consumption usage list`) ne renvoie pas les montants sur cet abonnement (`pretaxCost: None` sur les 62 lignes d'octobre). Le relevé se fait donc dans le portail.

## Estimé

### Méthode

- **Prix** : [Azure Retail Prices API](https://prices.azure.com/api/retail/prices), en EUR, région `spaincentral`, tarif à l'usage, relevé le 2026-10-15.
- **Quantités** : ressources réelles du cluster, relevées avec `az` le 2026-10-15 :
  - 2 nœuds `Standard_B2als_v2` ;
  - disque OS de 128 Go en **Premium SSD** (P10) par nœud, la valeur par défaut d'AKS ;
  - 1 disque PVC de 1 Go en Standard SSD (E1) ;
  - 3 IP publiques Standard : la sortie du cluster, poll et result ;
  - 1 Load Balancer Standard avec 2 règles + 1 règle sortante ;
  - un ACR Basic contenant 0,26 Go d'images.
- **Conversion** : 1 mois = 30,4 jours. Le control plane AKS est gratuit en tier Free.

### Cluster allumé

| Poste | Calcul | €/jour |
|---|---|---|
| 2 VM `B2als_v2` | 2 × 0,043 €/h × 24 | 2,06 |
| 2 disques OS P10 (128 Go Premium) | 2 × 19,08 €/mois | 1,26 |
| Load Balancer Standard (≤ 5 règles) | 0,022 €/h × 24 | 0,53 |
| 3 IP publiques Standard | 3 × 0,0044 €/h × 24 | 0,32 |
| ACR Basic (10 Go inclus) | 0,1466 €/jour | 0,15 |
| Disque PVC E1 (1 Go) | 0,264 €/mois | 0,01 |
| **Total** | | **≈ 4,3 €/jour (≈ 131 €/mois)** |

### Cluster arrêté (`az aks stop`)

Les VM ne sont plus facturées. Les disques OS des nœuds sont supprimés avec les instances : c'est à confirmer dans le portail après un arrêt. Les IP publiques, le Load Balancer, l'ACR et le disque PVC restent facturés.

| Poste | €/jour |
|---|---|
| IP publiques + Load Balancer + ACR + PVC | **≈ 1,0** |

### Écart avec l'ADR-0001

L'[ADR-0001](../adr/0001-plateforme-aks-acr.md) estimait 2,5 à 3 €/jour, avec 0,2 €/jour de disques. Il ignorait que le disque OS par défaut d'AKS est un **Premium SSD de 128 Go**, qui coûte à lui seul 1,26 €/jour, soit **30 % du total**. L'ADR n'est pas réécrit : l'écart est corrigé ici et repris dans la rétrospective.

## Ce que ça représente sur le crédit

Avec un crédit de 100 $ (≈ 92 €), moins les 12,54 € déjà dépensés :

| Usage | Durée du crédit restant (≈ 80 €) |
|---|---|
| Cluster allumé en permanence | ≈ 18 jours |
| Allumé 4 h par jour de travail, arrêté le reste | ≈ 1,0 + 4/24 × 3,3 ≈ 1,6 €/jour → ≈ 50 jours |

## Réductions possibles

| Action | Gain estimé | Contrepartie |
|---|---|---|
| Arrêter le cluster hors séances (`az aks stop`) | ≈ 3,3 €/jour arrêté | Démarrage de quelques minutes, capacité non garantie (ADR-0002) |
| Disque OS de 30 Go (P4, 5,11 €/mois) au lieu de 128 Go (`--node-osdisk-size 30` sur un nouveau pool de nœuds) | ≈ 0,92 €/jour | Recréer le pool de nœuds. 30 Go suffisent pour les images utilisées (0,26 Go) |
| Disque OS en Standard SSD | Plus encore | Démarrage des pods plus lent |
| Une seule IP publique avec un Ingress | ≈ 0,1 €/jour | Voir [ADR-0004](../adr/0004-exposition-loadbalancer.md) |
| Supprimer tout (`az group delete`) entre deux phases du projet | Tout | Tout recréer (≈ 10 min avec le README) |
