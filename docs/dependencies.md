# Dépendances

Relevé le 2026-10-15 dans le dépôt et sur le cluster.

## Fournisseurs et services

| Dépendance | Usage | Quota / limite connue | En cas d'indisponibilité |
|---|---|---|---|
| Microsoft Azure (Azure for Students) | AKS, ACR, disques, IP publiques | Crédit de 100 $. **6 vCPU régionaux**. Régions autorisées par politique : Sweden Central, Austria East, Germany West Central, Spain Central, Italy North ([ADR-0002](adr/0002-region-spain-central.md)) | Plus de déploiement possible. Le dépôt reste portable (manifestes Kubernetes standard, seuls les scripts `az` changent) |
| Docker Hub | Images de base `python:3.14-slim`, `node:24-slim`, `maven`, `eclipse-temurin:25-jre`, `redis:8`, `postgres:18` | Limite de téléchargements anonymes | Les builds et le démarrage des pods Redis et PostgreSQL échouent |
| CDN publics (Google, jQuery, BootstrapCDN) | AngularJS, jQuery, Font Awesome, chargés par le navigateur | — | Pages sans style ni interactivité (voir [docs/legal](legal/README.md), risques 3 et 4) |

## Images et versions

| Image | Tag utilisé | Version réellement tirée | Risque |
|---|---|---|---|
| `redis` | `8` | 8.10.2 | **Tag flottant** : un redémarrage peut tirer une nouvelle version mineure |
| `postgres` | `18` | 18.x | Tag flottant, même risque. Un changement de version majeure exigerait une migration des données |
| `poll`, `worker`, `result` | tag par déploiement (`v3`, hash git) | — | Aucun : les tags sont immuables |

Amélioration : fixer les tags (`redis:8.10.2`) ou les empreintes (`redis@sha256:…`).

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

## Outils de l'opérateur

`az` (Azure CLI), `docker`, `kubectl`, `envsubst` (gettext). Pour les mesures : `curl` (`scripts/probe.sh`) et `grafana/k6` (`scripts/load-test.js`).
