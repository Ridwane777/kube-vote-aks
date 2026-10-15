# ADR-0008 : Mises à jour sans coupure, sondes et ressources

- **Statut :** Accepté
- **Date :** 2026-10-15
- **Décideurs :** Ridwane

## Contexte

Le sujet exige une mise à jour « *without any downtime* », mesurée par un client qui interroge l'application en continu. Le cluster n'a que 2 petits nœuds (2 vCPU, 4 Go chacun). Les mesures et les incidents sont détaillés dans [docs/performance](../performance/README.md).

## Options envisagées

| Sujet | Options | Choix |
|---|---|---|
| Stratégie de mise à jour | RollingUpdate / Recreate / blue-green (2 Deployments et bascule du Service) / canary (Argo Rollouts, Flagger) | **RollingUpdate**, `maxSurge: 1`, `maxUnavailable: 0` : intégré à Kubernetes, aucun outil de plus |
| Savoir qu'un pod est prêt | Aucune sonde / readiness seule / readiness + liveness + startup | **Les trois**, sur les endpoints fournis par l'application |
| Arrêt des anciens pods | Arrêt immédiat / `preStop` + arrêt propre | **`preStop` de 10 s**, plus un arrêt propre de result sur `SIGTERM` |
| Ressources | Rien (QoS BestEffort) / `requests` / `requests` + `limits` | **`requests` CPU et mémoire, `limits` mémoire** |
| Serveur de poll | Commande de l'image (1 worker gunicorn *sync*) / commande surchargée / nouveau Dockerfile | **Commande surchargée dans le manifeste** |

## Décision

- **Sondes** :
  - `readinessProbe` sur `/readyz` (le pod reçoit du trafic seulement si ses dépendances répondent) ;
  - `livenessProbe` sur `/healthz` uniquement : une panne de Redis ou de PostgreSQL ne doit pas faire redémarrer tous les pods en boucle ;
  - `startupProbe` pour le worker Java ;
  - `timeoutSeconds: 2` sur poll.
- **`preStop: sleep 10`** sur poll et result : l'ancien pod continue de répondre pendant que le Load Balancer et kube-proxy cessent de lui envoyer du trafic. Le pod s'arrête ensuite.
- **Ressources (requests / limite mémoire)** :

  | Application | CPU demandé | Mémoire demandée | Limite mémoire |
  |---|---|---|---|
  | poll | 50m | 64Mi | 128Mi |
  | worker | 100m | 256Mi | 512Mi |
  | result | 50m | 64Mi | 192Mi |

  Pas de limite CPU : elle ralentirait les pods (*throttling*) même quand le nœud est libre.
- **poll** : gunicorn lancé avec `--worker-class gthread --workers 2 --threads 4`, au lieu du worker *sync* unique de l'image.
- **Répartition** : `topologySpreadConstraints` sur `kubernetes.io/hostname`, en mode souple (`ScheduleAnyway`) pour poll et result.

## Conséquences

### ✅ Gagné

- Mesuré pendant le déploiement de `v3` par `scripts/deploy.sh` : **0 erreur** (poll 65/65, result 65/65).
- Les crashs en boucle de poll après son exposition publique sont corrigés.
- Le scheduler place les pods selon leurs `requests`. Le QoS *Burstable* les protège mieux qu'un QoS *BestEffort* quand un nœud manque de mémoire.

### ❌ Perdu / risques

- **Un échec résiduel** sur result quand un second déploiement démarre avant la fin du premier (1 essai sur 3). Cause non identifiée.
- **Les valeurs de ressources sont estimées, pas mesurées** (aucun `kubectl top` sous charge). Elles sont à revoir après un test de charge.
- **Les mises à jour sont plus lentes**, à cause des 10 s de `preStop` par pod remplacé.
- **Répartition souple** : sous contrainte de capacité, deux réplicas peuvent encore partager un nœud.
- **La commande de poll est dupliquée** dans le manifeste : si le Dockerfile change, la surcharge doit suivre.
- **Pas d'autoscaling (HPA)** : 2 réplicas fixes. Avec 2 nœuds de petite taille, la marge pour monter en charge est faible.

### Quand changer

- **HPA** sur poll et result une fois la capacité mesurée.
- **PodDisruptionBudget** (`minAvailable: 1`) pour protéger les applications pendant les maintenances de nœuds AKS.
- **Canary** si une mauvaise version doit être détectée avant de servir tout le trafic.
