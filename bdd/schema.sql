-- =====================================================================
-- MediPlan — schema.sql
-- Modèle Physique des Données (MPD) · PostgreSQL >= 13
-- Plateforme de prise de rendez-vous médicaux (données de santé / HDS)
--
-- Conventions :
--   - Clés primaires UUID (gen_random_uuid) : identifiants non devinables (EBIOS R4 / IDOR)
--   - Statuts contraints par CHECK (évolutifs, lisibles)
--   - Horodatage en TIMESTAMPTZ (fuseau)
--   - ON DELETE : RESTRICT par défaut ; SET NULL pour liens optionnels ;
--                 CASCADE uniquement pour rappel -> rendez_vous
--   - Droit à l'oubli : par anonymisation (patient.anonymise), jamais par DELETE
--
-- Lancement (voir README) :
--   createdb mediplan && psql -d mediplan -f schema.sql
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- fournit gen_random_uuid()

-- =====================================================================
-- BLOC 1 — Comptes & praticiens
-- =====================================================================

CREATE TABLE specialite (
    id_specialite  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    libelle        TEXT NOT NULL UNIQUE,
    description    TEXT
);

CREATE TABLE utilisateur (
    id_utilisateur UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    keycloak_sub   TEXT UNIQUE,                 -- pont vers le compte Keycloak (auth déléguée)
    nom            TEXT NOT NULL,
    prenom         TEXT NOT NULL,
    email          TEXT NOT NULL UNIQUE,
    role           TEXT NOT NULL CHECK (role IN ('medecin', 'secretariat', 'admin')),
    actif          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE praticien (
    id_praticien   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    utilisateur_id UUID NOT NULL UNIQUE          -- relation 1:1 avec le compte
                   REFERENCES utilisateur(id_utilisateur) ON DELETE RESTRICT,
    specialite_id  UUID NOT NULL
                   REFERENCES specialite(id_specialite) ON DELETE RESTRICT,
    numero_rpps    TEXT NOT NULL UNIQUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- BLOC 2 — Cœur métier
-- =====================================================================

CREATE TABLE patient (
    id_patient     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    keycloak_sub   TEXT UNIQUE,                  -- nullable : un patient créé au guichet peut ne pas avoir de compte
    nom            TEXT NOT NULL,
    prenom         TEXT NOT NULL,
    date_naissance DATE NOT NULL,
    email          TEXT,
    telephone      TEXT,
    anonymise      BOOLEAN NOT NULL DEFAULT FALSE,   -- droit à l'oubli (EBIOS R5)
    anonymise_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE salle (
    id_salle       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nom            TEXT NOT NULL UNIQUE,
    localisation   TEXT,
    capacite       INT CHECK (capacite > 0)
);

CREATE TABLE equipement (
    id_equipement  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    salle_id       UUID NOT NULL
                   REFERENCES salle(id_salle) ON DELETE RESTRICT,
    libelle        TEXT NOT NULL,
    numero_serie   TEXT UNIQUE,
    statut         TEXT NOT NULL DEFAULT 'disponible'
                   CHECK (statut IN ('disponible', 'maintenance', 'hors_service'))
);

CREATE TABLE creneau (
    id_creneau     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    praticien_id   UUID NOT NULL
                   REFERENCES praticien(id_praticien) ON DELETE RESTRICT,
    gestionnaire_id UUID NOT NULL                 -- médecin ou secrétariat qui gère le planning
                   REFERENCES utilisateur(id_utilisateur) ON DELETE RESTRICT,
    debut          TIMESTAMPTZ NOT NULL,
    fin            TIMESTAMPTZ NOT NULL,
    statut         TEXT NOT NULL DEFAULT 'libre'
                   CHECK (statut IN ('libre', 'reserve', 'bloque')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT creneau_fin_apres_debut CHECK (fin > debut),
    CONSTRAINT creneau_unique_praticien_debut UNIQUE (praticien_id, debut)
);

CREATE TABLE rendez_vous (
    id_rdv         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id     UUID NOT NULL
                   REFERENCES patient(id_patient) ON DELETE RESTRICT,
    praticien_id   UUID NOT NULL
                   REFERENCES praticien(id_praticien) ON DELETE RESTRICT,
    creneau_id     UUID NOT NULL UNIQUE          -- 1 RDV par créneau : anti double-réservation
                   REFERENCES creneau(id_creneau) ON DELETE RESTRICT,
    salle_id       UUID                          -- optionnel
                   REFERENCES salle(id_salle) ON DELETE SET NULL,
    motif          TEXT,
    statut         TEXT NOT NULL DEFAULT 'planifie'
                   CHECK (statut IN ('planifie', 'confirme', 'annule', 'honore')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rappel (
    id_rappel      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rendez_vous_id UUID NOT NULL
                   REFERENCES rendez_vous(id_rdv) ON DELETE CASCADE,  -- pas de rappel sans RDV
    canal          TEXT NOT NULL CHECK (canal IN ('email', 'sms')),
    statut_envoi   TEXT NOT NULL DEFAULT 'en_attente'
                   CHECK (statut_envoi IN ('en_attente', 'envoye', 'echec')),
    date_envoi     TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- BLOC 3 — RGPD & sécurité (tables ajoutées au niveau physique)
-- =====================================================================

CREATE TABLE consentement (
    id_consentement   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id        UUID NOT NULL
                      REFERENCES patient(id_patient) ON DELETE RESTRICT,
    finalite          TEXT NOT NULL
                      CHECK (finalite IN ('prise_rdv', 'rappels', 'traitement_donnees')),
    version           TEXT NOT NULL,             -- version du texte de consentement accepté
    statut            TEXT NOT NULL DEFAULT 'accorde'
                      CHECK (statut IN ('accorde', 'retire')),
    date_consentement TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE dossier_medical (
    id_dossier          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id          UUID NOT NULL UNIQUE     -- 1:1 avec le patient
                        REFERENCES patient(id_patient) ON DELETE RESTRICT,
    numero_secu_chiffre BYTEA,                    -- NIR chiffré CÔTÉ APPLICATION (clé hors base) — EBIOS R1
    groupe_sanguin      TEXT CHECK (groupe_sanguin IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    antecedents         TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE journal_acces (
    id_acces       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    utilisateur_id UUID                          -- nullable : la trace survit à la suppression du compte
                   REFERENCES utilisateur(id_utilisateur) ON DELETE SET NULL,
    acteur_email   TEXT NOT NULL,                -- dénormalisé : conserve l'identité même si le compte disparaît
    action         TEXT NOT NULL
                   CHECK (action IN ('lecture', 'creation', 'modification', 'suppression')),
    ressource_type TEXT NOT NULL,                -- ex. 'dossier_medical', 'patient', 'rendez_vous'
    ressource_id   UUID,
    horodatage     TIMESTAMPTZ NOT NULL DEFAULT now(),
    adresse_ip     INET
);

-- =====================================================================
-- Index sur les clés étrangères et colonnes de recherche
-- (PostgreSQL n'indexe pas automatiquement les FK)
-- =====================================================================

CREATE INDEX idx_praticien_specialite   ON praticien(specialite_id);
CREATE INDEX idx_equipement_salle       ON equipement(salle_id);
CREATE INDEX idx_creneau_praticien      ON creneau(praticien_id);
CREATE INDEX idx_creneau_gestionnaire   ON creneau(gestionnaire_id);
CREATE INDEX idx_creneau_debut          ON creneau(debut);
CREATE INDEX idx_rdv_patient            ON rendez_vous(patient_id);
CREATE INDEX idx_rdv_praticien          ON rendez_vous(praticien_id);
CREATE INDEX idx_rdv_salle              ON rendez_vous(salle_id);
CREATE INDEX idx_rdv_statut             ON rendez_vous(statut);
CREATE INDEX idx_rappel_rdv             ON rappel(rendez_vous_id);
CREATE INDEX idx_consentement_patient   ON consentement(patient_id);
CREATE INDEX idx_journal_utilisateur    ON journal_acces(utilisateur_id);
CREATE INDEX idx_journal_ressource      ON journal_acces(ressource_type, ressource_id);
CREATE INDEX idx_journal_horodatage     ON journal_acces(horodatage);

-- =====================================================================
-- Commentaires (traçabilité EBIOS)
-- =====================================================================

COMMENT ON TABLE  dossier_medical              IS 'Données de santé cloisonnées — accès restreint (EBIOS R1)';
COMMENT ON COLUMN dossier_medical.numero_secu_chiffre IS 'NIR chiffré côté application, la clé ne réside jamais en base (EBIOS R1)';
COMMENT ON TABLE  journal_acces                IS 'Journal d''audit en écriture seule (EBIOS R1, R2)';
COMMENT ON COLUMN patient.anonymise            IS 'Droit à l''oubli : TRUE = patient pseudonymisé, pas supprimé (EBIOS R5)';
COMMENT ON CONSTRAINT creneau_unique_praticien_debut ON creneau IS 'Empêche deux créneaux identiques pour un même praticien';
