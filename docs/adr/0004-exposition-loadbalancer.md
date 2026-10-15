# ADR-0004 : Exposition de poll et result par deux Services `LoadBalancer`

- **Statut :** Accepté — configuration du Service `result` (affinité, `Local`) remplacée par [ADR-0005](0005-result-websocket-sans-affinite.md)
- **Date :** 2026-10-15
- **Décideurs :** Ridwane

## Contexte

Le sujet exige que les pages Poll et Result soient « *accessible from the outside world* ». En soutenance, l'équipe peut donner au correcteur « *the external IP addresses* » : aucun nom de domaine ni HTTPS n'est demandé. Une mise à jour doit se faire sans aucune erreur pour un client qui interroge l'application en continu.

Contrainte technique : result utilise Socket.IO en transport **polling uniquement** (`result/views/app.js` : `transports:['polling']`). Chaque session (`sid`) n'existe que sur le pod qui l'a créée. Avec 2 réplicas, toutes les requêtes d'un même client doivent arriver au même pod (affinité de session).

## Options envisagées

| Critère | **A. 2 Services `LoadBalancer`** | B. Ingress Traefik | C. AKS App Routing (Ingress NGINX managé) |
|---|---|---|---|
| IP publiques | 2 | 1 | 1 |
| Coût estimé de l'IP publique | ~2 × 0,12 €/jour | ~0,12 €/jour, plus les ressources du contrôleur | ~0,12 €/jour |
| Affinité pour result | `sessionAffinity: ClientIP`, natif | Cookie à configurer sur l'Ingress | Cookie à configurer |
| HTTPS / domaine | Non, à faire Service par Service | Centralisé (cert-manager) | Centralisé |
| Composant à installer | Aucun | Contrôleur (Helm) | Add-on (`az aks approuting enable`) |
| Déploiement par le correcteur | `kubectl apply -f k8s/` | Étape d'installation de plus | Étape Azure de plus |

## Décision

**Option A.** Les Services `poll` et `result` passent en `type: LoadBalancer`. Azure crée une IP publique pour chacun sur son Load Balancer Standard.

Le Service `result` est configuré avec :

- `sessionAffinity: ClientIP` : un même client est toujours envoyé au même pod ;
- `externalTrafficPolicy: Local` : le trafic n'est envoyé qu'aux nœuds qui hébergent un pod result, **sans traduction d'adresse source**. Le Service voit donc l'IP réelle du client. Avec la politique par défaut (`Cluster`), un paquet peut traverser un autre nœud et arriver avec l'IP de ce nœud, ce qui casse l'affinité.

## Vérification (2026-10-15)

- `poll` → `203.0.113.10`, `result` → `203.0.113.20` : HTTP 200 sur les deux. Ces IP changent si les Services sont recréés.
- 4 ouvertures de session Socket.IO successives depuis le même client : les `sid` sont séquentiels (`…AAAD`, `…AAAE`, `…AAAF`, `…AAAG`). Ce compteur est propre à chaque processus serveur, donc les 4 requêtes ont été servies par le même pod.

## Conséquences

### ✅ Gagné

- Exigence du sujet couverte, sans composant supplémentaire. Tout se déploie avec `kubectl apply -f k8s/`.
- L'affinité de result fonctionne sans configuration de proxy.
- Le Load Balancer Azure vérifie la santé des nœuds. Avec les readinessProbes, un pod en cours de remplacement ne reçoit pas de trafic.

### ❌ Perdu / risques

- **Pas de HTTPS** : les votes circulent en clair. C'est acceptable pour une démonstration, mais pas pour une vraie élection.
- **Pas de nom de domaine** : les IP sont dynamiques et changent si le Service est supprimé. Une IP statique Azure est possible (`loadBalancerIP` + annotation de resource group).
- **Une IP par application** : le coût et la surface d'exposition augmentent avec le nombre d'applications.
- **Affinité `ClientIP` grossière** : tous les utilisateurs derrière un même NAT (école, entreprise) vont sur le même pod.
- **`externalTrafficPolicy: Local`** : un nœud sans pod result ne reçoit pas de trafic. Si les 2 pods sont sur le même nœud, ce nœud porte toute la charge, d'où l'intérêt d'une règle de répartition des pods.

### Quand changer

Un Ingress (option B ou C) devient préférable dès qu'il faut **HTTPS**, un **nom de domaine**, ou plus de **2 ou 3 applications** exposées. Dans ce cas, l'affinité de result passerait par un cookie de l'Ingress.

## Liens

- [ADR-0001](0001-plateforme-aks-acr.md), [ADR-0003](0003-manifestes-yaml-postgres-statefulset.md)
- Manifestes : `k8s/30-poll.yaml`, `k8s/50-result.yaml`
