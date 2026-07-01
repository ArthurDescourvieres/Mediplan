# MediPlan — POC : chiffrement des données de santé au repos + RBAC

Preuve de faisabilité (spike) de la principale mesure de réduction du risque **critique** identifié par l'analyse EBIOS. Le POC démontre qu'un vol de la base de données ne permet pas de lire les données de santé, et que l'accès à ces données dépend du rôle de l'utilisateur.

## Lien avec l'analyse de risques (EBIOS)

| Risque | Description | Mesure prouvée par le POC |
|---|---|---|
| **R1** (critique, criticité 12) | Fuite / exfiltration de données de santé | Chiffrement **AES-256-GCM au repos**, clé hors base → un dump SQL volé reste illisible |
| **R2** (élevé) | Compromission d'un compte | **RBAC** → un compte compromis ne peut lire que ce que son rôle autorise |

R1 est le risque retenu pour le POC. Références : `docs/analyse-risques-v2.pdf` et `poc/ADR-001-rbac-applicatif-vs-rls.pdf` (choix du RBAC applicatif plutôt que PostgreSQL RLS).

## Périmètre

### Ce que le POC prouve
- Le NIR (`numero_secu`) est stocké **chiffré** dans `dossier_medical.numero_secu_chiffre` (`BYTEA`) : illisible en base.
- Le déchiffrement n'est possible **qu'avec la clé**, conservée **hors base** (variable d'environnement).
- L'accès au dossier médical déchiffré est **filtré par le rôle** de l'utilisateur (contrôle applicatif).

### Hors périmètre (volontairement — c'est un spike, pas l'application)
- Pas d'interface utilisateur.
- Pas d'authentification réelle : le rôle est simulé (paramètre), Keycloak n'est pas branché.
- Pas de coffre à secrets (Vault / KMS) : la clé est dans un `.env` pour la démonstration.
- Pas de PostgreSQL RLS : voir `ADR-001` (retenu comme durcissement de production).

## Choix techniques

| Élément | Choix | Raison |
|---|---|---|
| Langage | Node.js / TypeScript | Cohérent avec l'API NestJS du CDC |
| Chiffrement | AES-256-GCM | Chiffrement authentifié (confidentialité + intégrité) |
| Clé | Variable d'environnement (`.env`) | La clé ne réside **jamais** en base (exigence R1) |
| Base | PostgreSQL — `dossier_medical.numero_secu_chiffre` (`BYTEA`) | La table conçue dans `bdd/schema.sql` |
| Contrôle d'accès | RBAC applicatif (façon *Guard* NestJS) | Voir `ADR-001` |
| Donnée chiffrée | `numero_secu` (NIR) | Donnée de santé la plus sensible |

## Rôles et droits

| Rôle | Données administratives (`patient`) | Dossier médical (`dossier_medical`) |
|---|---|---|
| `medecin` | oui | **oui** (NIR déchiffré) |
| `secretariat` | oui (adresse, contact, infos de base) | **non** |
| `admin` | gestion des comptes | **non** |

Seul le `medecin` accède au contenu médical déchiffré. Le `secretariat` se limite au dossier administratif ; l'`admin` administre les comptes sans voir le médical.

## Scénario de démonstration

1. **Chiffrer** un NIR et l'insérer dans `dossier_medical` → un `SELECT` montre un `BYTEA` illisible.
2. Lecture par un **`medecin`** → le NIR est déchiffré et lisible.
3. Lecture tentée par un **`secretariat`** ou un **`admin`** → **accès refusé** par le contrôle de rôle.
4. **Sans la clé** (ou avec une mauvaise clé) → déchiffrement impossible → un dump volé est **inexploitable**.

## Structure prévue du dossier `poc/`

```
poc/
├── ADR-001-rbac-applicatif-vs-rls.pdf   # décision d'architecture (fait)
├── README.md                            # ce fichier (fait)
├── src/                                 # code du spike (à réaliser sur le repo de l'équipe)
├── .env.example                         # exemple de clé de chiffrement
└── package.json
```

La partie **code** sera réalisée dans l'environnement de développement, sur le dépôt Git de l'équipe.

## Lancement (prévu)

Prérequis : Node.js ≥ 18 et une base PostgreSQL chargée (voir `bdd/README.md`).

```bash
cp .env.example .env      # définir la clé de chiffrement (CLE_CHIFFREMENT)
npm install
npm run demo              # déroule le scénario de démonstration ci-dessus
```

> Les commandes définitives seront figées avec le code.

## Limites et suite (durcissement en production)

- **PostgreSQL RLS** : contrôle d'accès au plus près de la donnée, en complément du RBAC applicatif (`ADR-001`).
- **Gestion des clés** via un coffre (Vault / KMS) et **rotation** régulière, plutôt qu'un `.env`.
- **Authentification réelle** (Keycloak) et mapping des rôles vers les *Guards*.
- **Moindre privilège** sur les comptes PostgreSQL.

## Références

- `docs/analyse-risques-v2.pdf` — analyse EBIOS (R1, R2)
- `poc/ADR-001-rbac-applicatif-vs-rls.pdf` — décision RBAC applicatif vs RLS
- `bdd/schema.sql` — table `dossier_medical` (`numero_secu_chiffre BYTEA`)
