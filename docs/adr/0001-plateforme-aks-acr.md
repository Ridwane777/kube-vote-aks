# ADR-0001 : Plateforme d'hébergement — AKS + ACR en Poland Central

- **Statut :** Accepté — région et resource group remplacés par [ADR-0002](0002-region-spain-central.md)
- **Date :** 2026-10-15
- **Décideurs :** Ridwane

## Contexte

Le sujet Bernstein impose :

- un cluster Kubernetes **multi-nœuds** ;
- un **registre Docker privé** pour les images `poll`, `worker` et `result` ;
- que l'évaluateur puisse cloner le dépôt et redéployer **à partir d'un cluster prêt à l'emploi sur la même plateforme**.

Contraintes propres à l'équipe :

- budget : crédits **Azure for Students** (100 $), dont **12,54 € déjà consommés** par la VM du bootstrap (mesuré, Cost Management) ;
- quotas mesurés en Poland Central (`az vm list-usage`, 2026-10-14) : **6 vCPU régionaux** au total, famille BS limitée à 4 vCPU, familles Basv2 / Bsv2 à 10 vCPU ;
- `Standard_B2s` est **restreinte** pour cet abonnement en Poland Central ; `Standard_B2als_v2` et `Standard_B2s_v2` sont disponibles (`az vm list-skus`) ;
- le resource group `bernstein-rg` existe déjà en **Poland Central**.

## Options envisagées

| Option | Description |
|---|---|
| **A. AKS + ACR** (Azure) | Kubernetes managé, control plane géré par Azure, registre privé managé |
| B. k3s sur plusieurs VM Azure | Cluster monté à la main sur 2–3 VM, registre auto-hébergé |
| C. Autre cloud managé (GKE, EKS, DigitalOcean) | Kubernetes managé hors Azure |
| D. Minikube sur une VM | Ce qui a servi au bootstrap |

### Comparaison

| Critère | A. AKS + ACR | B. k3s sur VM | C. Autre cloud | D. Minikube |
|---|---|---|---|---|
| Multi-nœuds (exigé) | ✅ | ✅ | ✅ | ❌ un seul nœud |
| Registre privé | ✅ ACR, auth par identité managée | ⚠️ à installer et sécuriser soi-même | ✅ | ❌ |
| IP publique (`LoadBalancer`) | ✅ native | ⚠️ MetalLB / NodePort à configurer | ✅ | ❌ |
| Reproductible par l'évaluateur | ✅ « cluster prêt à l'emploi » | ⚠️ dépend de notre installation | ✅ | ❌ |
| Coût pour nous | Crédits étudiants existants | Crédits, plus de VM | Pas de crédits ou crédits limités | Faible |
| Charge d'exploitation | Faible (control plane managé) | Élevée (mises à jour, etcd, certificats) | Faible | — |

## Décision

**Option A : AKS (tier Free) + ACR (Basic) dans `bernstein-rg`, en Poland Central.**

- **Nœuds :** 2 × `Standard_B2als_v2` (2 vCPU, 4 Go chacun), soit 4 vCPU sur les 6 du quota régional.
- **Registre :** ACR Basic relié au cluster par `--attach-acr` : les nœuds tirent les images grâce à leur identité managée, **sans secret de registre** dans Kubernetes.
- **Région :** Poland Central, celle du resource group existant. Tout dans la même région = pas de frais de transfert entre régions, données hébergées dans l'UE.
- **Exploitation :** cluster arrêté (`az aks stop`) en dehors des séances de travail.

## Conséquences

### ✅ Gagné

- Exigences du sujet couvertes : multi-nœuds, registre privé, exposition externe par `LoadBalancer`.
- Pas d'installation ni de maintenance du control plane (etcd, API server, certificats).
- Aucun identifiant de registre à gérer : l'accès ACR passe par l'identité managée.
- 2 nœuds permettent de démontrer `kubectl drain` et la répartition des réplicas.
- 2 vCPU de quota restent libres, pour un nœud temporaire lors d'une mise à jour de version AKS (surge).

### ❌ Perdu / risques

- **Dépendance à Azure** : les scripts (`az aks`, `az acr`) ne sont pas portables tels quels vers un autre cloud. Les manifestes Kubernetes, eux, le restent.
- **Pas d'autoscaling des nœuds utile** : 3 nœuds au maximum dans le quota (6 vCPU).
- **Pas de haute disponibilité multi-zone** : avec 2 nœuds, la perte d'un nœud laisse la moitié de la capacité.
- **Tier Free** : pas de SLA sur le control plane (le tier Standard en a un, mais il est payant).
- **Coût récurrent** : l'ACR et les disques sont facturés même quand le cluster est arrêté. Il n'y a pas d'alerte de budget (choix de l'équipe), le risque d'oubli repose sur la discipline `az aks stop`.

### Coûts estimés

Ce sont des estimations à confirmer avec l'Azure Pricing Calculator et à remplacer par les montants mesurés dans Cost Management.

| Poste | Cluster allumé | Cluster arrêté |
|---|---|---|
| 2 × `B2als_v2` | ~1,5–2 €/jour | 0 € |
| Load Balancer Standard + IP publique | ~0,6 €/jour | ~0,1 €/jour (IP) |
| ACR Basic | ~0,15 €/jour | ~0,15 €/jour |
| Disques OS des nœuds et PVC | ~0,2 €/jour | ~0,2 €/jour |

## Liens

- Sujet : [`docs/bernstein-project.md`](../bernstein-project.md)
- Remplace : —
- Remplacé par : [ADR-0002](0002-region-spain-central.md) (région et resource group)
