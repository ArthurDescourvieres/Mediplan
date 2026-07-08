#!/usr/bin/env bash
# =====================================================================
# MediPlan — initialisation de la base de donnees
# Usage :  ./init.sh [nom_base]      (defaut : mediplan)
# Prerequis : PostgreSQL >= 13 installe et demarre, commandes
#             createdb / psql accessibles dans le PATH.
# =====================================================================
set -euo pipefail

DB="${1:-mediplan}"   # nom de la base, modifiable en argument

# (Optionnel) repartir d'une base vierge :
# dropdb --if-exists "$DB"

# 1) Creation de la base de donnees
createdb "$DB"

# 2) Creation de la structure : tables, contraintes, index
psql -d "$DB" -f schema.sql

# 3) Insertion des donnees de test
psql -d "$DB" -f seed.sql

echo "Base '$DB' prete : structure + donnees de test chargees."
