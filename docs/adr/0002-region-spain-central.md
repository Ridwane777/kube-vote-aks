# ADR-0002 : Région Spain Central et resource group `bernstein-spain-rg`

- **Statut :** Accepté
- **Date :** 2026-10-15
- **Décideurs :** Ridwane
- **Remplace :** [ADR-0001](0001-plateforme-aks-acr.md), pour la région et le resource group uniquement. Le choix AKS + ACR, le tier Free et les 2 nœuds `Standard_B2als_v2` restent valables.

## Contexte

L'ADR-0001 prévoyait AKS et ACR en **Poland Central**, dans le resource group `bernstein-rg`. La création a échoué plusieurs fois, pour trois raisons différentes :

| Région | Résultat | Cause (message Azure) |
|---|---|---|
| Poland Central | ❌ ACR refusé | `RequestDisallowedByAzure` : la politique d'abonnement *Allowed resource deployment regions* n'autorise que `swedencentral`, `austriaeast`, `germanywestcentral`, `spaincentral`, `italynorth`. Le resource group, lui, avait pu être créé en Poland Central |
| Germany West Central | ❌ AKS refusé | `BadRequest` : aucune taille de série B autorisée pour AKS ; les tailles D/F v6-v7 proposées ont un quota de **0 vCPU** |
| Sweden Central | ❌ AKS en échec | `AllocationFailed` : capacité `B2als_v2` insuffisante dans la région au moment de la création |
| Italy North | non testé | Aucune taille B2 disponible (`az vm list-skus`) |
| Austria East | non testé | Tailles B2 v2 disponibles, gardé en réserve |
| **Spain Central** | ✅ | Création AKS réussie |

Pendant ces essais, le resource group `bernstein-rg` a été supprimé depuis le portail. Pour ne pas attendre la fin de sa suppression, un nouveau groupe a été créé.

## Options envisagées

1. **Spain Central**, même taille `B2als_v2`.
2. **Austria East**, même taille.
3. **Sweden Central** avec une taille plus grande (`B2s_v2`, 8 Go) : environ 2 fois plus cher par nœud.
4. Réessayer Sweden Central plus tard : délai inconnu.
5. Demander une augmentation de quota D/F en Germany West Central : réponse incertaine sur Azure for Students.

## Décision

**Option 1 : tout en Spain Central, dans le nouveau resource group `bernstein-spain-rg`.**

- ACR : `myregistry.azurecr.io` (Basic) ;
- AKS : `bernstein-aks`, Kubernetes 1.35, tier Free, 2 × `Standard_B2als_v2`, relié à l'ACR (`--attach-acr`).

## Conséquences

### ✅ Gagné

- Taille et coût prévus par l'ADR-0001 conservés.
- ACR et AKS dans la même région : pas de frais de transfert entre régions pour le téléchargement des images.
- Région dans l'UE, dans la liste autorisée de l'abonnement.
- Austria East reste une solution de repli testée sur le papier.

### ❌ Perdu / risques

- **Capacité non garantie** : un `az aks start` après un arrêt peut, comme en Suède, échouer faute de VM disponibles. Le cluster resterait alors arrêté jusqu'au retour de la capacité.
- **Latence** depuis la France un peu plus élevée qu'avec l'Allemagne : négligeable pour cette application.
- **Le nom du resource group change** : tous les scripts et la documentation doivent utiliser `bernstein-spain-rg`.
- **Leçon retenue** : vérifier la politique de régions, les tailles autorisées **pour AKS** et le quota de la région **avant** d'écrire l'ADR de plateforme. À reporter dans la rétrospective.

## Liens

- [ADR-0001](0001-plateforme-aks-acr.md)
