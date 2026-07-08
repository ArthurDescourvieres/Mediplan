// Rôles reconnus dans MediPlan (cohérent avec le CHECK de la table utilisateur).
export type Role = 'medecin' | 'secretariat' | 'admin';

/**
 * RBAC applicatif — mesure de réduction du risque EBIOS R2
 * (compromission d'un compte : on limite ce qu'un rôle peut lire).
 *
 * Règle métier (voir guide spike) : seul le médecin accède au NIR déchiffré.
 * Le secrétariat et l'admin sont refusés.
 */
export function peutLireDossierMedical(role: Role): boolean {
  return role === 'medecin';
}