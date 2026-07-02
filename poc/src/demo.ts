// IMPORTANT : charger le .env AVANT d'importer les modules qui lisent process.env.
// chiffrement.ts lit CLE_CHIFFREMENT au chargement → dotenv doit passer en premier.
import 'dotenv/config';

import { chiffrer, dechiffrer } from './chiffrement';
import { connecter, enregistrerNirChiffre, lireNirChiffre } from './bdd';
import { peutLireDossierMedical, Role } from './guard';

// Patient cible (existe dans le seed) et NIR fictif à protéger.
const PATIENT_ID = '00000066-0000-0000-0000-000000000001';
const NIR_EN_CLAIR = '1 84 12 75 116 001 42';

// Simule une lecture de dossier par un rôle donné : le Guard décide, puis on déchiffre.
function lireDossier(role: Role, blob: Buffer): void {
  if (!peutLireDossierMedical(role)) {
    console.log(`  [${role}] ❌ accès refusé au dossier médical (RBAC)`);
    return;
  }
  const nir = dechiffrer(blob);
  console.log(`  [${role}] ✅ NIR déchiffré : ${nir}`);
}

async function main() {
  const client = await connecter();
  try {
    console.log('\n=== 1. Chiffrement et stockage ===');
    const blob = chiffrer(NIR_EN_CLAIR);
    await enregistrerNirChiffre(client, PATIENT_ID, blob);
    console.log(`  NIR en clair : ${NIR_EN_CLAIR}`);

    // Relecture du blob brut tel qu'il est stocké en base (ce que verrait un attaquant).
    const blobEnBase = await lireNirChiffre(client, PATIENT_ID);
    console.log('\n=== 2. Ce qui est réellement stocké (dump volé) ===');
    console.log(`  BYTEA en base : ${blobEnBase?.toString('hex')}`);
    console.log('  → illisible sans la clé.');

    console.log('\n=== 3. Contrôle d\'accès par rôle (RBAC) ===');
    if (blobEnBase) {
      lireDossier('medecin', blobEnBase);
      lireDossier('secretariat', blobEnBase);
      lireDossier('admin', blobEnBase);
    }

    console.log('\n=== 4. Tentative avec une mauvaise clé ===');
    try {
      // On simule un attaquant qui a le dump mais pas la bonne clé.
      const mauvaiseCle = Buffer.alloc(32, 0); // 32 octets de zéros
      const crypto = require('crypto');
      if (blobEnBase) {
        const iv = blobEnBase.subarray(0, 12);
        const tag = blobEnBase.subarray(12, 28);
        const chiffre = blobEnBase.subarray(28);
        const d = crypto.createDecipheriv('aes-256-gcm', mauvaiseCle, iv);
        d.setAuthTag(tag);
        Buffer.concat([d.update(chiffre), d.final()]);
      }
    } catch {
      console.log('  ❌ déchiffrement impossible avec une mauvaise clé (GCM rejette).');
      console.log('  → un dump volé est inexploitable. Faisabilité R1 prouvée.');
    }
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('Erreur :', err);
  process.exit(1);
});