import crypto from 'crypto';

// Algorithme : AES en mode GCM, clé de 256 bits.
// GCM = chiffrement + authentification (détecte toute altération des données).
const ALGO = 'aes-256-gcm';

// La clé vient de l'environnement (.env), stockée en hexadécimal, jamais en base.
// Buffer.from(..., 'hex') la convertit en 32 octets bruts (256 bits).
// EBIOS R1 : la clé hors base rend un dump volé inexploitable.
const CLE = Buffer.from(process.env.CLE_CHIFFREMENT as string, 'hex');

/**
 * Chiffre une chaîne (le NIR) et retourne un Buffer prêt à stocker en BYTEA.
 * Format de sortie : IV (12o) || authTag (16o) || données chiffrées.
 */
export function chiffrer(nir: string): Buffer {
  // 1. IV (vecteur d'initialisation) : 12 octets aléatoires, neufs à CHAQUE chiffrement.
  //    C'est ce qui fait que chiffrer 2x le même NIR donne 2 résultats différents.
  const iv = crypto.randomBytes(12);

  // 2. Créer le cipher avec l'algo, la clé et l'IV.
  const cipher = crypto.createCipheriv(ALGO, CLE, iv);

  // 3. Chiffrer : update() traite les données, final() clôt l'opération.
  //    On concatène les deux morceaux dans un seul Buffer.
  const chiffre = Buffer.concat([cipher.update(nir, 'utf8'), cipher.final()]);

  // 4. Récupérer le tag d'authentification (16 octets) produit par GCM.
  //    Il scelle les données : toute modif ultérieure sera détectée au déchiffrement.
  const authTag = cipher.getAuthTag();

  // 5. Concaténer IV || authTag || données chiffrées → c'est ce qui part en base.
  return Buffer.concat([iv, authTag, chiffre]);
}

/**
 * Déchiffre un Buffer (relu depuis la base) et retourne le NIR en clair.
 * Découpe l'inverse : IV (12o) || authTag (16o) || données chiffrées.
 */
export function dechiffrer(blob: Buffer): string {
  // 1. Redécouper les 3 morceaux selon leurs longueurs fixes.
  const iv = blob.subarray(0, 12);
  const authTag = blob.subarray(12, 28);   // 12 + 16
  const chiffre = blob.subarray(28);

  // 2. Créer le decipher avec l'algo, la clé et l'IV d'origine.
  const decipher = crypto.createDecipheriv(ALGO, CLE, iv);

  // 3. Fournir le tag AVANT de déchiffrer : GCM vérifiera l'intégrité.
  //    Si les données ou la clé sont mauvaises, final() lèvera une erreur.
  decipher.setAuthTag(authTag);

  // 4. Déchiffrer et reconstituer la chaîne d'origine.
  const dechiffre = Buffer.concat([decipher.update(chiffre), decipher.final()]);
  return dechiffre.toString('utf8');
}