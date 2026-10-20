# Dépendances

Relevé le 2026-10-15 dans le dépôt et sur le cluster.

## Fournisseurs et services

| Dépendance | Usage | Quota / limite connue | En cas d'indisponibilité |
|---|---|---|---|
| Microsoft Azure (Azure for Students) | AKS, ACR, disques, IP publiques | Crédit de 100 $. **6 vCPU régionaux**. Régions autorisées par politique : Sweden Central, Austria East, Germany West Central, Spain Central, Italy North ([ADR-0002](adr/0002-region-spain-central.md)) | Plus de déploiement possible. Le dépôt reste portable (manifestes Kubernetes standard, seuls les scripts `az` changent) |
| Docker Hub | Images de base `python:3.14-slim`, `node:24-slim`, `maven`, `eclipse-temurin:25-jre`, `redis:8.10.2`, `postgres:18.6` | Limite de téléchargements anonymes | Les builds et le démarrage des pods Redis et PostgreSQL échouent |
| Jenkins (`jenkins/jenkins:lts`) sur le VPS d'un membre (jenkins.example.com:8090) | Déploiement, arrêt et redémarrage depuis un lien (`Jenkinsfile`, [ADR-0011](adr/0011-deploiement-jenkins.md)) | Ressources du VPS (8 vCPU, 23 Go) ; plugin *Docker Pipeline* requis | Plus de lien de déploiement ; la procédure en ligne de commande reste disponible |
| GitHub Actions | Alternative à Jenkins (`.github/workflows/deploy.yml`, [ADR-0010](adr/0010-deploiement-github-actions.md)) | **Minutes de l'organisation épuisées** (relevé le 2026-10-20) | Workflow inutilisable jusqu'à la remise à zéro mensuelle |
| CDN publics (Google, jQuery, BootstrapCDN) | AngularJS, jQuery, Font Awesome, chargés par le navigateur | — | Pages sans style ni interactivité (voir [docs/legal](legal/README.md), risques 3 et 4) |

## Images et versions

| Image | Tag utilisé | Version réellement tirée | Risque |
|---|---|---|---|
| `redis` | `8.10.2` (fixé le 2026-10-18) | 8.10.2 | Aucun. Avant : `8`, un tag flottant |
| `postgres` | `18.6` (fixé le 2026-10-18) | 18.6 | Aucun. Avant : `18`. Un changement de version majeure exigerait une migration des données |
| `poll`, `worker`, `result` | tag par déploiement (`v3`, hash git) | — | Aucun : les tags sont immuables |

Amélioration restante : fixer les empreintes (`redis@sha256:…`) pour se protéger d'un tag republié.

## Bibliothèques

| Application | Dépendances principales | Licences |
|---|---|---|
| poll | Flask 3.1.3, redis-py 8.1.0, gunicorn 26.2.0 | BSD-3-Clause, MIT, MIT |
| worker | Jedis 8.0.1, pilote PostgreSQL 42.7.13, org.json 20260814 | MIT, BSD-2-Clause, Public Domain (JSON License) |
| result | Express 5, Socket.IO 4.8, pg 8, async 3 (105 paquets au total dans `package-lock.json`) | 98 MIT, 6 ISC, 1 BSD-3-Clause |
| Navigateur | AngularJS 1.4.5, jQuery (`latest`), Font Awesome 4.4.0 | MIT, MIT, SIL OFL / MIT |
| Services | Redis 8 | RSALv2 / SSPLv1 / AGPLv3 (au choix) |
| | PostgreSQL 18 | PostgreSQL License (permissive) |

## Secrets

| Secret | Où il vit | Dans le dépôt ? |
|---|---|---|
| Identifiants Azure | `~/.azure/` sur le poste de l'opérateur | Non |
| Accès au cluster | `~/.kube/config` | Non |
| Accès ACR depuis AKS | Identité managée du cluster (`--attach-acr`), aucun mot de passe | Non |
| `POSTGRES_PASSWORD` | Secret Kubernetes `postgres-secret`, créé par `scripts/deploy.sh` à partir d'une variable d'environnement | Non |
| Mot de passe du service principal `bernstein-jenkins-deploy` (Contributor sur `bernstein-spain-rg`) | Credentials Jenkins `azure-deploy-sp`, masqué dans les journaux. **Expire** (1 an par défaut) : `az ad sp credential reset` | Non |
| Token GitHub en lecture du dépôt | Credentials Jenkins `github-bernstein`. Expiration choisie à la création | Non |
| Accès Azure de GitHub Actions | Identité fédérée OIDC, aucun mot de passe | Non |

## Outils de l'opérateur

`az` (Azure CLI), `docker`, `kubectl`, `envsubst` (gettext). Jenkins n'a besoin que de Docker : les autres outils sont dans l'image `ci/Dockerfile`. Pour les mesures : `curl` (`scripts/probe.sh`) et `grafana/k6` (`scripts/load-test.js`).
