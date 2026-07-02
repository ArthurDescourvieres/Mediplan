import { Client } from 'pg';

// Crée et connecte un client PostgreSQL à partir de DATABASE_URL (.env).
export async function connecter(): Promise<Client> {
  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  return client;
}

// Enregistre le NIR chiffré (Buffer) dans le dossier médical d'un patient.
// Requête paramétrée ($1, $2) → protège contre l'injection SQL (EBIOS R4).
export async function enregistrerNirChiffre(
  client: Client,
  patientId: string,
  nirChiffre: Buffer
): Promise<void> {
  await client.query(
    'UPDATE dossier_medical SET numero_secu_chiffre = $1 WHERE patient_id = $2',
    [nirChiffre, patientId]
  );
}

// Relit la colonne chiffrée telle qu'elle est stockée en base (BYTEA → Buffer).
// C'est ce Buffer brut qu'on montrera "illisible", puis qu'on déchiffrera.
export async function lireNirChiffre(
  client: Client,
  patientId: string
): Promise<Buffer | null> {
  const res = await client.query(
    'SELECT numero_secu_chiffre FROM dossier_medical WHERE patient_id = $1',
    [patientId]
  );
  // Si pas de ligne ou colonne NULL, on renvoie null.
  return res.rows[0]?.numero_secu_chiffre ?? null;
}