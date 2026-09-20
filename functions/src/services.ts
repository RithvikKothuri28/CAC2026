import { Auth } from 'firebase-admin/auth';
import { FieldValue, Firestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { documentId, JsonMap, sanitizePassport } from './validation';

export async function requireFarmAccess(db: Firestore, farmId: string, uid: string, ownerOnly = false): Promise<void> {
  const [farm, deletion] = await Promise.all([
    db.doc(`farms/${farmId}`).get(), db.doc(`accountDeletionRequests/${uid}`).get(),
  ]);
  if (deletion.exists || !farm.exists || farm.get('deletionState') === 'deleting') {
    throw new HttpsError('permission-denied', 'This farm is unavailable to this account.');
  }
  const ownerId = farm.get('ownerId');
  if ((await db.doc(`accountDeletionRequests/${ownerId}`).get()).exists) {
    throw new HttpsError('permission-denied', 'This farm is being removed.');
  }
  if (ownerId === uid) return;
  if (!ownerOnly) {
    const member = await db.doc(`farms/${farmId}/members/${uid}`).get();
    if (['viewer', 'editor'].includes(member.get('role'))) return;
  }
  throw new HttpsError('permission-denied', 'You do not have permission for this farm.');
}

export async function publishPassport(db: Firestore, uid: string, farmId: string, batchId: string, fields: unknown): Promise<{ passportId: string }> {
  const farmRef = db.doc(`farms/${farmId}`);
  const batchRef = farmRef.collection('harvestBatches').doc(batchId);
  // Re-publication replaces the same public document, removing any deselected fields.
  const mappingRef = farmRef.collection('passportPublications').doc(batchId);
  return db.runTransaction(async (tx) => {
    const [farm, batch, mapping, deletion] = await Promise.all([
      tx.get(farmRef), tx.get(batchRef), tx.get(mappingRef), tx.get(db.doc(`accountDeletionRequests/${uid}`)),
    ]);
    if (deletion.exists || !farm.exists || farm.get('ownerId') !== uid || farm.get('deletionState') === 'deleting') {
      throw new HttpsError('permission-denied', 'Only the farm owner may publish a passport.');
    }
    if (!batch.exists) throw new HttpsError('not-found', 'Harvest batch does not exist.');
    const safe = sanitizePassport(batch.get('data'), fields);
    const passportId = mapping.exists ? documentId(mapping.get('passportId'), 'Passport ID') : db.collection('publicHarvestPassports').doc().id;
    tx.set(db.doc(`publicHarvestPassports/${passportId}`), { ...safe, publishedAt: FieldValue.serverTimestamp() });
    tx.set(mappingRef, { passportId, batchId, publishedAt: FieldValue.serverTimestamp() });
    return { passportId };
  });
}

export async function unpublishPassport(db: Firestore, uid: string, farmId: string, passportId: string): Promise<void> {
  await requireFarmAccess(db, farmId, uid, true);
  const mappings = await db.collection(`farms/${farmId}/passportPublications`).where('passportId', '==', passportId).get();
  if (mappings.empty) throw new HttpsError('not-found', 'This passport is not published by this farm.');
  const batch = db.batch();
  batch.delete(db.doc(`publicHarvestPassports/${passportId}`));
  for (const mapping of mappings.docs) batch.delete(mapping.ref);
  await batch.commit();
}

async function deletePublishedPassports(db: Firestore, farmId: string): Promise<void> {
  // Paginate to bound memory and writes for arbitrary farms.
  for (;;) {
    const mappings = await db.collection(`farms/${farmId}/passportPublications`).limit(200).get();
    if (mappings.empty) return;
    const batch = db.batch();
    for (const mapping of mappings.docs) {
      batch.delete(db.doc(`publicHarvestPassports/${documentId(mapping.get('passportId'), 'Passport ID')}`));
      batch.delete(mapping.ref);
    }
    await batch.commit();
  }
}

/** Durable freeze makes failed recursive deletion safe to retry and prevents new descendants. */
export async function removeFarm(db: Firestore, uid: string, farmId: string): Promise<void> {
  const farmRef = db.doc(`farms/${farmId}`);
  const job = db.doc(`farmDeletionRequests/${farmId}`);
  await db.runTransaction(async (tx) => {
    const [farm, previousJob] = await Promise.all([tx.get(farmRef), tx.get(job)]);
    if (!farm.exists && previousJob.exists && previousJob.get('ownerId') === uid) return;
    if (!farm.exists || farm.get('ownerId') !== uid) throw new HttpsError('permission-denied', 'Only the farm owner can delete this farm.');
    tx.set(job, { ownerId: uid, farmId, requestedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(farmRef, { deletionState: 'deleting' });
  });
  await deletePublishedPassports(db, farmId);
  await db.recursiveDelete(farmRef);
  await job.delete();
}

export async function queueAccountDeletion(db: Firestore, uid: string): Promise<void> {
  await db.doc(`accountDeletionRequests/${uid}`).set({ requestedAt: FieldValue.serverTimestamp() }, { merge: true });
}

export async function removeAccountData(db: Firestore, auth: Auth, uid: string): Promise<void> {
  await queueAccountDeletion(db, uid);
  for (;;) {
    const owned = await db.collection('farms').where('ownerId', '==', uid).limit(20).get();
    if (owned.empty) break;
    for (const farm of owned.docs) await removeFarm(db, uid, farm.id);
  }
  // Membership userId is validated by rules, so cleanup does not need to scan every farm.
  for (;;) {
    const memberships = await db.collectionGroup('members').where('userId', '==', uid).limit(200).get();
    if (memberships.empty) break;
    const batch = db.batch();
    for (const member of memberships.docs) batch.delete(member.ref);
    await batch.commit();
  }
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.recursiveDelete(db.doc(`aiUsage/${uid}`));
  // Existing ID tokens can survive account deletion until expiry. Block all old-token writes.
  await db.doc(`deletedAccounts/${uid}`).set({ expiresAt: Timestamp.fromMillis(Date.now() + 86400000) });
  try { await auth.deleteUser(uid); }
  catch (error) {
    if ((error as { code?: string }).code !== 'auth/user-not-found') throw error;
  }
  await db.doc(`accountDeletionRequests/${uid}`).delete();
}

export async function consumeAiQuota(db: Firestore, uid: string, limits: { user: number; global: number; intervalSeconds: number }, now = new Date()): Promise<void> {
  const day = now.toISOString().slice(0, 10);
  const userRef = db.doc(`aiUsage/${uid}/days/${day}`);
  const globalRef = db.doc(`aiGlobalUsage/${day}`);
  await db.runTransaction(async (tx) => {
    const [user, global] = await Promise.all([tx.get(userRef), tx.get(globalRef)]);
    const userCount = Number(user.get('count') ?? 0);
    const globalCount = Number(global.get('count') ?? 0);
    const last = user.get('lastRequestAt') as Timestamp | undefined;
    if (userCount >= limits.user || globalCount >= limits.global
      || (last && now.getTime() - last.toMillis() < limits.intervalSeconds * 1000)) {
      throw new HttpsError('resource-exhausted', 'Cloud explanation quota reached. Use the local explanation.');
    }
    const entry: JsonMap = { count: userCount + 1, lastRequestAt: Timestamp.fromDate(now), expiresAt: Timestamp.fromMillis(now.getTime() + 7 * 86400000) };
    tx.set(userRef, entry);
    tx.set(globalRef, { count: globalCount + 1, expiresAt: entry.expiresAt });
  });
}
