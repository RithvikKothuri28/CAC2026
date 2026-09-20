const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, query, where, serverTimestamp, enableNetwork, disableNetwork, waitForPendingWrites, setLogLevel } = require('firebase/firestore');
const { initializeApp: clientApp, deleteApp: deleteClientApp } = require('firebase/app');
const { getAuth: clientAuth, connectAuthEmulator, createUserWithEmailAndPassword, signOut, signInWithEmailAndPassword } = require('firebase/auth');
const { initializeApp: adminApp, deleteApp: deleteAdminApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { publishPassport, unpublishPassport, removeFarm, removeAccountData, requireFarmAccess, consumeAiQuota } = require('../lib/services');

const projectId = 'demo-farmtwin';
// Permission-denied writes are deliberate assertions; keep test output legible.
setLogLevel('silent');
if (process.env.GCLOUD_PROJECT !== projectId || !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '') || !/^127\.0\.0\.1:\d+$/.test(process.env.FIREBASE_AUTH_EMULATOR_HOST || '')) {
  throw new Error('Tests require isolated loopback emulators and project demo-farmtwin. Refusing all other targets.');
}
let environment, admin, db;
const farm = (ownerId = 'owner') => ({ schemaVersion: 1, ownerId, name: 'Security fixture farm', source: 'userEntered', data: { fields: [], crops: [] }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
const entity = (data) => ({ schemaVersion: 1, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), data });
const privateDb = (uid) => environment.authenticatedContext(uid).firestore();
async function seed() {
  const owner = privateDb('owner');
  await setDoc(doc(owner, 'farms/farm-a'), farm());
  await setDoc(doc(owner, 'farms/farm-a/members/viewer'), { userId: 'viewer', role: 'viewer' });
  await setDoc(doc(owner, 'farms/farm-a/members/editor'), { userId: 'editor', role: 'editor' });
  await setDoc(doc(owner, 'farms/farm-a/harvestBatches/batch-a'), entity({ crop: 'Fixture crop', field: 'Fixture field', notes: 'Unpublished private note', financials: { revenue: 9500 }, ownerId: 'owner', inputRecords: [{ name: 'Farmer input', date: '2026-03-01' }] }));
  await setDoc(doc(privateDb('outsider'), 'farms/farm-b'), farm('outsider'));
}
before(async () => {
  environment = await initializeTestEnvironment({ projectId, firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') } });
  admin = adminApp({ projectId }, 'farmtwin-backend-tests');
  db = getFirestore(admin);
});
beforeEach(async () => { await environment.clearFirestore(); });
after(async () => { await environment.cleanup(); await deleteAdminApp(admin); });

test('private farms reject anonymous and cross-account reads/writes', async () => {
  await seed();
  for (const client of [environment.unauthenticatedContext().firestore(), privateDb('outsider')]) {
    await assertFails(getDoc(doc(client, 'farms/farm-a')));
    await assertFails(getDoc(doc(client, 'farms/farm-a/harvestBatches/batch-a')));
    await assertFails(updateDoc(doc(client, 'farms/farm-a'), { name: 'Stolen', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(client, 'farms/farm-a/expenses/injected'), entity({ amount: 20 })));
  }
  const own = await assertSucceeds(getDocs(query(collection(privateDb('owner'), 'farms'), where('ownerId', '==', 'owner'))));
  assert.equal(own.size, 1);
  await assertFails(getDocs(collection(privateDb('owner'), 'farms')));
});

test('viewer cannot edit, publish or mutate ownership; editor cannot escalate', async () => {
  await seed();
  const viewer = privateDb('viewer'), editor = privateDb('editor'), owner = privateDb('owner');
  await assertSucceeds(getDoc(doc(viewer, 'farms/farm-a')));
  await assertFails(updateDoc(doc(viewer, 'farms/farm-a'), { name: 'Viewer change', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(viewer, 'farms/farm-a/expenses/expense'), entity({ amount: 12 })));
  await assertFails(setDoc(doc(viewer, 'farms/farm-a/members/viewer'), { userId: 'viewer', role: 'editor' }));
  await assert.rejects(publishPassport(db, 'viewer', 'farm-a', 'batch-a', ['crop']), { code: 'permission-denied' });
  await assert.rejects(removeFarm(db, 'viewer', 'farm-a'), { code: 'permission-denied' });
  await assertSucceeds(updateDoc(doc(editor, 'farms/farm-a'), { name: 'Edited farm', updatedAt: serverTimestamp() }));
  for (const client of [editor, owner]) await assertFails(updateDoc(doc(client, 'farms/farm-a'), { ownerId: 'editor', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(editor, 'farms/farm-a/members/outsider'), { userId: 'outsider', role: 'editor' }));
  await assertFails(setDoc(doc(owner, 'farms/farm-a/members/outsider'), { userId: 'outsider', role: 'owner' }));
  await assertFails(deleteDoc(doc(owner, 'farms/farm-a')));
});

test('allowlisted entities persist create, update, read, delete; unknown schema and paths denied', async () => {
  const owner = privateDb('owner');
  await setDoc(doc(owner, 'farms/farm-a'), farm());
  for (const name of ['fields', 'cropProfiles', 'cropHistory', 'expenses', 'debts', 'constraints', 'scenarios', 'optimizationRuns', 'simulationRuns', 'harvestBatches', 'settings']) {
    const ref = doc(owner, `farms/farm-a/${name}/fixture`);
    await assertSucceeds(setDoc(ref, entity({ value: 12 })));
    await assertSucceeds(updateDoc(ref, { data: { value: 18 }, updatedAt: serverTimestamp() }));
    assert.equal((await getDoc(ref)).data().data.value, 18);
    await assertSucceeds(deleteDoc(ref));
    assert.equal((await getDoc(ref)).exists(), false);
  }
  await assertFails(setDoc(doc(owner, 'farms/farm-a/unknown/fixture'), entity({ value: 12 })));
  await assertFails(setDoc(doc(owner, 'farms/farm-a/expenses/fixture'), { ...entity({ amount: 10 }), ownerId: 'owner' }));
  await assertFails(updateDoc(doc(owner, 'farms/farm-a'), { schemaVersion: 99, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(owner, 'aiUsage/owner'), { count: 0 }));
  await assertFails(setDoc(doc(owner, 'accountDeletionRequests/owner'), { requestedAt: serverTimestamp() }));
});

test('published passport is anonymous get-only and cannot leak private source data', async () => {
  await seed();
  const result = await publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop', 'inputRecords']);
  const anonymous = environment.unauthenticatedContext().firestore();
  const ref = doc(anonymous, `publicHarvestPassports/${result.passportId}`);
  const published = (await assertSucceeds(getDoc(ref))).data();
  assert.deepEqual(Object.keys(published).sort(), ['crop', 'inputRecords', 'provenance', 'publishedAt', 'schemaVersion', 'selectedFields'].sort());
  for (const key of ['financials', 'notes', 'ownerId', 'farmId', 'batchId', 'field']) assert.equal(key in published, false);
  await assertFails(getDocs(collection(anonymous, 'publicHarvestPassports')));
  await assertFails(setDoc(doc(privateDb('owner'), `publicHarvestPassports/${result.passportId}`), published));
  await assert.rejects(publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop', 'financials']), { code: 'invalid-argument' });
  const replaced = await publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop']);
  assert.equal(replaced.passportId, result.passportId);
  assert.equal('inputRecords' in (await getDoc(ref)).data(), false);
  await db.doc('farms/farm-a').update({ source: 'sample' });
  await publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop']);
  assert.equal((await getDoc(ref)).data().provenance, 'sample');
  await assert.rejects(unpublishPassport(db, 'outsider', 'farm-b', result.passportId), { code: 'not-found' });
  await unpublishPassport(db, 'owner', 'farm-a', result.passportId);
  assert.equal((await getDoc(ref)).exists(), false);
  await unpublishPassport(db, 'owner', 'farm-a', result.passportId);
  assert.equal((await getDoc(ref)).exists(), false);
});

test('farm deletion recursively cleans private descendants and public passports', async () => {
  await seed();
  const { passportId } = await publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop']);
  await db.doc('farms/farm-a/scenarios/scenario/nested/private').set({ sensitive: true });
  await removeFarm(db, 'owner', 'farm-a');
  for (const document of ['farms/farm-a', 'farms/farm-a/members/viewer', 'farms/farm-a/harvestBatches/batch-a', 'farms/farm-a/scenarios/scenario/nested/private', `publicHarvestPassports/${passportId}`, 'farmDeletionRequests/farm-a']) {
    assert.equal((await db.doc(document).get()).exists, false, document);
  }
  assert.equal((await db.doc('farms/farm-b').get()).exists, true);
});

test('account deletion cleans farms, passports, memberships, settings and auth identity', async () => {
  await seed();
  await getAuth(admin).createUser({ uid: 'owner', email: 'owner@example.test', password: 'Fixture-only-password42' }).catch((error) => { if (error.code !== 'auth/uid-already-exists') throw error; });
  await db.doc('users/owner/preferences/private').set({ value: 'sensitive' });
  await db.doc('farms/farm-b/members/owner').set({ userId: 'owner', role: 'viewer' });
  const { passportId } = await publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop']);
  await removeAccountData(db, getAuth(admin), 'owner');
  assert.equal((await db.doc(`publicHarvestPassports/${passportId}`).get()).exists, false);
  assert.equal((await db.doc('farms/farm-a').get()).exists, false);
  assert.equal((await db.doc('farms/farm-b/members/owner').get()).exists, false);
  assert.equal((await db.doc('users/owner/preferences/private').get()).exists, false);
  assert.equal((await db.doc('farms/farm-b').get()).exists, true);
  await assert.rejects(getAuth(admin).getUser('owner'), { code: 'auth/user-not-found' });
  await assertFails(setDoc(doc(privateDb('owner'), 'farms/resurrected'), farm()));
  // A different owner re-adding a stale UID must not revive its old-token access.
  await db.doc('farms/farm-b/members/owner').set({ userId: 'owner', role: 'viewer' });
  await assert.rejects(requireFarmAccess(db, 'farm-b', 'owner'), { code: 'permission-denied' });
});

test('deletion freeze denies edits and server publication during retry window', async () => {
  await seed();
  await db.doc('farms/farm-a').update({ deletionState: 'deleting' });
  await assertFails(setDoc(doc(privateDb('owner'), 'farms/farm-a/expenses/late'), entity({ amount: 10 })));
  await assert.rejects(publishPassport(db, 'owner', 'farm-a', 'batch-a', ['crop']), { code: 'permission-denied' });
  await db.doc('accountDeletionRequests/outsider').set({ requestedAt: new Date() });
  await assertFails(setDoc(doc(privateDb('outsider'), 'farms/new-farm'), farm('outsider')));
  await db.doc('deletedAccounts/viewer').set({ expiresAt: new Date(Date.now() + 86400000) });
  await assert.rejects(requireFarmAccess(db, 'farm-a', 'viewer'), { code: 'permission-denied' });
  await db.doc('deletedAccounts/outsider').set({ expiresAt: new Date(Date.now() + 86400000) });
  await db.doc('accountDeletionRequests/outsider').delete();
  await db.doc('farms/farm-b/harvestBatches/batch-b').set({ data: { crop: 'Fixture crop' } });
  await assert.rejects(publishPassport(db, 'outsider', 'farm-b', 'batch-b', ['crop']), { code: 'permission-denied' });
});

test('quota transaction prevents concurrent overspend; unauthorized context remains inaccessible', async () => {
  await seed();
  await assert.rejects(requireFarmAccess(db, 'farm-a', 'outsider'), { code: 'permission-denied' });
  const attempts = await Promise.allSettled(Array.from({ length: 8 }, () => consumeAiQuota(db, 'owner', { user: 3, global: 4, intervalSeconds: 0 }, new Date('2026-06-01T12:00:00Z'))));
  assert.equal(attempts.filter((attempt) => attempt.status === 'fulfilled').length, 3);
  await consumeAiQuota(db, 'outsider', { user: 3, global: 4, intervalSeconds: 0 }, new Date('2026-06-01T12:00:00Z'));
  await assert.rejects(consumeAiQuota(db, 'another', { user: 3, global: 4, intervalSeconds: 0 }, new Date('2026-06-01T12:00:00Z')), { code: 'resource-exhausted' });
});

test('account creation, persisted edits, offline queue, reopen and sign-in recover state', async () => {
  const application = clientApp({ projectId, apiKey: 'emulator-fixture-key', authDomain: 'localhost' }, 'lifecycle-fixture');
  const auth = clientAuth(application);
  connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  const email = `lifecycle-${Date.now()}@example.test`, password = 'Fixture-only-password42';
  try {
    const credential = await createUserWithEmailAndPassword(auth, email, password);
    const uid = credential.user.uid;
    const initialClient = privateDb(uid);
    await setDoc(doc(initialClient, 'farms/lifecycle'), farm(uid));
    await updateDoc(doc(initialClient, 'farms/lifecycle'), { data: { fields: [{ id: 'field-a', acres: 21 }], crops: [{ id: 'crop-a', price: 4 }], expenses: [{ amount: 12 }], debts: [{ payment: 3 }], constraints: [{ kind: 'water', limit: 50 }] }, updatedAt: serverTimestamp() });
    await setDoc(doc(initialClient, 'farms/lifecycle/optimizationRuns/run-a'), entity({ engineVersion: 1, operatingIncome: 69, inputRevision: 'fixture-1' }));
    await setDoc(doc(initialClient, 'farms/lifecycle/simulationRuns/run-a'), entity({ seed: 91, iterations: 100, mean: 68 }));
    await setDoc(doc(initialClient, 'farms/lifecycle/scenarios/scenario-a'), entity({ priceMultiplier: 0.8 }));
    await disableNetwork(initialClient);
    const pendingWrite = updateDoc(doc(initialClient, 'farms/lifecycle'), { name: 'Changed while offline', updatedAt: serverTimestamp() });
    const offline = await getDoc(doc(initialClient, 'farms/lifecycle'));
    assert.equal(offline.metadata.fromCache, true);
    assert.equal(offline.data().name, 'Changed while offline');
    await enableNetwork(initialClient);
    await pendingWrite;
    await waitForPendingWrites(initialClient);
    await initialClient.terminate();
    await signOut(auth);
    assert.equal(auth.currentUser, null);
    const signedBackIn = await signInWithEmailAndPassword(auth, email, password);
    assert.equal(signedBackIn.user.uid, uid);
    const reopened = privateDb(uid);
    const saved = (await getDoc(doc(reopened, 'farms/lifecycle'))).data();
    assert.equal(saved.name, 'Changed while offline');
    assert.equal(saved.data.fields[0].acres, 21);
    assert.equal((await getDoc(doc(reopened, 'farms/lifecycle/optimizationRuns/run-a'))).data().data.operatingIncome, 69);
    assert.equal((await getDoc(doc(reopened, 'farms/lifecycle/simulationRuns/run-a'))).data().data.seed, 91);
    assert.equal((await getDoc(doc(reopened, 'farms/lifecycle/scenarios/scenario-a'))).data().data.priceMultiplier, 0.8);
  } finally { await deleteClientApp(application); }
});
