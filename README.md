# MediPlan

> Refonte du système de prise de rendez-vous d'un hôpital régional.

**Statut : projet en cours de cadrage**

---

## Présentation

MediPlan est un projet de refonte complète du système de prise de rendez-vous d'un hôpital régional. L'objectif est de moderniser et simplifier le parcours patient — de la demande de rendez-vous jusqu'à la consultation — tout en facilitant le travail des équipes administratives et médicales.

---

## Structure du dépôt

| Dossier | Description |
|---|---|
| `docs/planning/` | Documentation de cadrage : cahier des charges, plannings, comptes rendus de réunion |
| `bdd/` | Schémas de base de données, modèles de données, migrations |
| `maquettes/` | Liens et exports des maquettes Figma (UI/UX) |
| `poc/` | Preuves de concept techniques (spikes implémentés) |
| `.github/ISSUE_TEMPLATE/` | Templates GitHub Issues : bug report, feature request, spike |

---

## Commandes utilisées pour initialiser le dépôt

```bash
# Création des labels GitHub
gh label create "bug"          --color "#d73a4a" --description "Anomalie ou comportement inattendu"
gh label create "feature"      --color "#0075ca" --description "Nouvelle fonctionnalité"
gh label create "spike"        --color "#e4e669" --description "Investigation technique"
gh label create "must-have"    --color "#b60205" --description "Priorité MoSCoW : indispensable"
gh label create "should-have"  --color "#e99695" --description "Priorité MoSCoW : important"
gh label create "could-have"   --color "#f9d0c4" --description "Priorité MoSCoW : utile si possible"
gh label create "wont-have"    --color "#cccccc" --description "Priorité MoSCoW : hors périmètre"
gh label create "in-progress"  --color "#0052cc" --description "En cours de développement"
gh label create "blocked"      --color "#b60205" --description "Bloqué, nécessite une action externe"
gh label create "review"       --color "#6f42c1" --description "En attente de relecture"

# Protection de la branche main (1 review requise, push direct interdit)
gh api repos/ArthurDescourvieres/Mediplan/branches/main/protection \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field required_status_checks=null \
  --field enforce_admins=true \
  --field 'required_pull_request_reviews[required_approving_review_count]=1' \
  --field 'required_pull_request_reviews[dismiss_stale_reviews]=true' \
  --field 'restrictions=null'
```
