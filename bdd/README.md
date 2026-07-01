# MediPlan — Base de données

Schéma physique et données de test de la plateforme de prise de rendez-vous médicaux MediPlan (données de santé, hébergement HDS). SGBD : **PostgreSQL ≥ 13**.

## Prérequis

- PostgreSQL **13 ou supérieur** (nécessaire pour `gen_random_uuid()`)
- Les commandes `createdb` et `psql` accessibles dans le `PATH`
- Un serveur PostgreSQL démarré et un utilisateur autorisé à créer une base

## Lancement (une commande)

```bash
./init.sh
```

Le script crée la base, charge la structure puis les données de test. Pour utiliser un autre nom de base : `./init.sh ma_base`.

> Si besoin, rendre le script exécutable une fois : `chmod +x init.sh`.

### Détail des 3 commandes exécutées par `init.sh`

```bash
# 1) Créer la base de données
createdb mediplan

# 2) Charger la structure : tables, contraintes, index
psql -d mediplan -f schema.sql

# 3) Charger les données de test
psql -d mediplan -f seed.sql
```

On peut aussi exécuter ces trois commandes à la main si l'on préfère ne pas passer par le script.

## Contenu du dossier

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `schema.sql` | Structure complète : 12 tables, contraintes, index, commentaires |
| `seed.sql` | Données de test fictives (à charger après `schema.sql`) |
| `init.sh` | Script de mise en route (les 3 commandes ci-dessus) |
| `mcd.png` | Modèle Conceptuel des Données (entités, associations, cardinalités) |
| `mld.png` | Modèle Logique des Données |
| `contraintes-rgpd.pdf` | Note explicative : contraintes & grain RGPD par niveau Merise |

## Requêtes de vérification

Une fois la base chargée, ces requêtes confirment que tout est en place.

```sql
-- Nombre de lignes par table principale
SELECT 'patients'   AS table, count(*) FROM patient
UNION ALL SELECT 'praticiens', count(*) FROM praticien
UNION ALL SELECT 'creneaux',   count(*) FROM creneau
UNION ALL SELECT 'rendez_vous',count(*) FROM rendez_vous;
```

```sql
-- Rendez-vous avec patient, praticien et horaire (jointures)
SELECT rv.statut,
       pat.nom  AS patient,
       u.nom    AS praticien,
       c.debut
FROM rendez_vous rv
JOIN patient    pat ON pat.id_patient    = rv.patient_id
JOIN praticien  pr  ON pr.id_praticien   = rv.praticien_id
JOIN utilisateur u  ON u.id_utilisateur  = pr.utilisateur_id
JOIN creneau    c   ON c.id_creneau      = rv.creneau_id
ORDER BY c.debut;
```

```sql
-- Vérifier l'anti double-réservation : aucun créneau ne doit porter 2 RDV
SELECT creneau_id, count(*)
FROM rendez_vous
GROUP BY creneau_id
HAVING count(*) > 1;   -- doit renvoyer 0 ligne
```

## Note RGPD — droit à l'oubli (anonymisation)

Conformément au RGPD, un patient n'est **jamais supprimé** (cela casserait l'intégrité des rendez-vous et du journal d'audit). Le droit à l'oubli est traité par **pseudonymisation** : on écrase les données personnelles et on purge le dossier médical, tout en conservant les enregistrements liés de façon anonyme.

Exemple (le patient n°15 du `seed.sql` illustre déjà l'état final) :

```sql
BEGIN;

-- 1) Pseudonymiser l'identité du patient
UPDATE patient
   SET nom          = 'ANONYMISE',
       prenom       = 'ANONYMISE',
       email        = NULL,
       telephone    = NULL,
       keycloak_sub = NULL,
       anonymise    = TRUE,
       anonymise_at = now()
 WHERE id_patient = '00000066-0000-0000-0000-000000000015';

-- 2) Purger les données de santé
UPDATE dossier_medical
   SET numero_secu_chiffre = NULL,
       groupe_sanguin      = NULL,
       antecedents         = NULL,
       notes               = NULL
 WHERE patient_id = '00000066-0000-0000-0000-000000000015';

-- 3) Retirer les consentements
UPDATE consentement
   SET statut = 'retire'
 WHERE patient_id = '00000066-0000-0000-0000-000000000015';

COMMIT;
```

Les rendez-vous passés restent en base mais ne sont plus rattachables à une personne identifiable. Ce lien avec l'analyse de risques EBIOS (R5 — conformité) est documenté dans `contraintes-rgpd.pdf`.

## Note sécurité — chiffrement

La colonne `dossier_medical.numero_secu_chiffre` est de type `BYTEA` : le numéro de sécurité sociale (NIR) est **chiffré côté application**, la clé ne réside jamais dans la base. Dans le `seed.sql`, cette colonne est volontairement laissée à `NULL`. La faisabilité de ce chiffrement est l'objet du POC technique (risque critique EBIOS R1 — fuite de données de santé).
