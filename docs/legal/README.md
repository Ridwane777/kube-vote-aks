# Analyse légale

Ce document couvre les données traitées par l'application de vote, les risques juridiques et les mesures à prendre avant une mise en service publique. Le projet est un **projet pédagogique** (the school), déployé temporairement pour une démonstration. Une mise en production réelle exigerait les actions marquées « à faire ».

## Données traitées

Relevé dans le code et sur le déploiement (2026-10-15) :

| Donnée | Où | Personnelle ? | Durée de conservation |
|---|---|---|---|
| `voter_id` : identifiant aléatoire (UUID) dans un cookie | Navigateur, Redis (en transit), PostgreSQL (`votes.id`) | **Oui, pseudonyme** (RGPD, considérant 26) : il identifie un navigateur | Cookie de session (pas de `Max-Age`, supprimé à la fermeture du navigateur). En base : **sans limite** |
| Choix du vote (a, b, c ou d) | PostgreSQL (`votes.vote`) | Oui, rattaché au `voter_id` | Sans limite |
| Adresse IP du visiteur | Connexions TCP vers le Load Balancer Azure et les pods | Oui | Non journalisée par l'application : gunicorn et Express n'ont pas de journal d'accès activé |
| Adresse IP envoyée aux CDN tiers | `ajax.googleapis.com` (AngularJS), `code.jquery.com` (jQuery), `maxcdn.bootstrapcdn.com` (Font Awesome) | Oui | Selon chaque fournisseur |

Aucune donnée d'identité (nom, e-mail, compte) n'est collectée.

## Risques et mesures

| # | Risque | Gravité | Mesure |
|---|---|---|---|
| 1 | **Pas de HTTPS** : cookie et votes circulent en clair et peuvent être lus ou modifiés sur le réseau | Élevée | À faire : TLS (Ingress + cert-manager, voir [ADR-0004](../adr/0004-exposition-loadbalancer.md)), puis cookie `Secure` |
| 2 | **Cookie sans `HttpOnly` ni `SameSite`** | Moyenne | À faire : `httponly=True, samesite='Lax'` dans `poll/app.py` |
| 3 | **Transferts vers des CDN tiers** (Google, jQuery, BootstrapCDN) sans information du visiteur. Google est soumis au droit américain | Moyenne | À faire : servir ces fichiers depuis l'application, ou informer le visiteur dans la politique de confidentialité |
| 4 | **Bibliothèques front obsolètes** : AngularJS 1.4.5 (fin de support fin 2021, failles XSS connues), `jquery-latest` (version figée ancienne) | Moyenne | À faire : mettre à jour ou supprimer les dépendances |
| 5 | **Conservation sans limite** des votes | Faible | À faire : définir une durée (par ex. supprimer les votes 30 jours après la fin du scrutin) |
| 6 | **Bannières techniques** : en-têtes `Server: gunicorn` et `X-Powered-By: Express` | Faible | À faire : les masquer (réduit les informations données à un attaquant) |
| 7 | **Le vote n'est pas un vote certifié** : un même votant peut voter plusieurs fois en supprimant son cookie | Information | À indiquer dans les conditions d'utilisation : sondage indicatif, pas un scrutin officiel |

### Cookie et consentement

Le cookie `voter_id` sert uniquement à ce qu'un navigateur n'ait qu'un vote, le dernier comptant. Il est nécessaire au service demandé par l'utilisateur. Selon la position de la CNIL sur les traceurs, il entre **probablement** dans l'exemption de consentement (article 82 de la loi Informatique et Libertés). L'information reste obligatoire : elle doit figurer dans la politique de confidentialité. Cette qualification est à confirmer si l'identifiant sert un jour à autre chose.

## Hébergement et sous-traitants

| Sous-traitant | Rôle | Localisation |
|---|---|---|
| Microsoft Azure | Cluster AKS, registre ACR, disques, IP publiques | **Spain Central** (Union européenne), voir [ADR-0002](../adr/0002-region-spain-central.md) |
| Google, jQuery Foundation (StackPath), BootstrapCDN | Fichiers JavaScript et CSS chargés par le navigateur | Hors contrôle du projet |

## Projet de politique de confidentialité

> **Qui traite vos données ?** L'équipe du projet Bernstein (the school), dans le cadre d'un projet pédagogique.
>
> **Quelles données ?** Un identifiant aléatoire stocké dans un cookie de session, et votre choix de vote. Aucune donnée permettant de vous identifier directement n'est demandée.
>
> **Pourquoi ?** Pour qu'un seul vote soit compté par navigateur et pour afficher les résultats (intérêt légitime, art. 6.1.f RGPD).
>
> **Combien de temps ?** Le cookie est supprimé à la fermeture du navigateur. Les votes sont conservés jusqu'à la fin de la démonstration, puis supprimés.
>
> **Où ?** Sur Microsoft Azure, dans l'Union européenne (Espagne). Les pages chargent aussi des fichiers depuis Google et d'autres CDN, qui reçoivent votre adresse IP.
>
> **Vos droits :** accès, effacement, opposition, et réclamation auprès de la CNIL. Le vote étant pseudonyme, indiquez la valeur de votre cookie `voter_id` pour exercer vos droits.

## Licences

Toutes les dépendances sont sous licences permissives ou compatibles avec une utilisation en service, sans modification. Le détail est dans [docs/dependencies.md](../dependencies.md). Point d'attention : **Redis 8** est distribué sous triple licence (RSALv2, SSPLv1 ou AGPLv3). Son utilisation comme service interne, sans modification, est compatible. En revanche, revendre Redis lui-même comme service géré ne le serait pas sans précaution.
