import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _Account extends Fake implements User {
  _Account(this.uid);
  @override
  final String uid;
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = _Account('owner');
}

class _Functions extends Fake implements FirebaseFunctions {}

class _Metadata extends Fake implements SnapshotMetadata {
  _Metadata({this.hasPendingWrites = false, this.isFromCache = false});
  @override
  final bool hasPendingWrites;
  @override
  final bool isFromCache;
}

// Controlled SDK test doubles; these are never application implementations.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this.value, {bool pending = false})
    : metadata = _Metadata(hasPendingWrites: pending);
  @override
  final String id;
  final Map<String, dynamic>? value;
  @override
  final SnapshotMetadata metadata;
  @override
  Map<String, dynamic>? data() => value;
}

// ignore: subtype_of_sealed_class
class _QueryDocument extends _Snapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(super.id, Map<String, dynamic> super.value, {super.pending});
  @override
  Map<String, dynamic> data() => value!;
}

class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot([
    this.docs = const [],
    bool pending = false,
    bool fromCache = false,
  ]) : metadata = _Metadata(hasPendingWrites: pending, isFromCache: fromCache);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  final SnapshotMetadata metadata;
}

/// Keeps cache delivery and write acknowledgements under test control. These
/// tests intentionally return cached records regardless of Firebase Auth, just
/// as the SDK can do while offline; the adapter must enforce its own boundary.
class _Firestore extends Fake implements FirebaseFirestore {
  final documents = <String, _Document>{};
  final queries =
      <String, StreamController<QuerySnapshot<Map<String, dynamic>>>>{};
  Completer<void>? commitGate;
  int batches = 0;
  @override
  WriteBatch batch() {
    batches++;
    return _Batch(this);
  }

  _Document document(String path) =>
      documents.putIfAbsent(path, () => _Document(this, path));
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
}

class _Batch extends Fake implements WriteBatch {
  _Batch(this.store);
  final _Firestore store;
  final changes = <String, Map<String, dynamic>>{};
  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    changes[document.path] = Map<String, dynamic>.from(data as Map);
  }

  @override
  Future<void> commit() async {
    if (store.commitGate != null) await store.commitGate!.future;
    for (final entry in changes.entries) {
      final document = store.document(entry.key);
      document.value = entry.value;
      document.writes++;
    }
  }
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _Firestore store;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      store.document('${this.path}/$path');
  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => this;
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => store.queries.putIfAbsent(path, () => StreamController()).stream;
}

// Mutation here deliberately models cache arrival and write acknowledgements.
// ignore: subtype_of_sealed_class, must_be_immutable
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _Firestore store;
  @override
  final String path;
  Map<String, dynamic>? value;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  int reads = 0;
  int writes = 0;
  bool pending = false;
  GetOptions? lastReadOptions;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    reads++;
    lastReadOptions = options;
    if (readGate != null) await readGate!.future;
    return _Snapshot(path.split('/').last, value, pending: pending);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    writes++;
    value = data;
    if (writeGate != null) await writeGate!.future;
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    writes++;
    value = {...?value, ...Map<String, dynamic>.from(data)};
    if (writeGate != null) await writeGate!.future;
  }

  @override
  Future<void> delete() async {
    writes++;
    value = null;
    if (writeGate != null) await writeGate!.future;
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late _Firestore store;
  late FirestoreFarmRepository repository;
  late Farm farm;
  late _Document parent;

  setUp(() {
    auth = _Auth();
    store = _Firestore();
    repository = FirestoreFarmRepository(store, auth, _Functions());
    farm = FarmDataCodec.decodeFarm(
      jsonDecode(File('test/fixtures/farm.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    parent = store.document('farms/${farm.id}')
      ..value = {'ownerId': 'owner', 'schemaVersion': 1, 'data': farm.toJson()};
    addTearDown(repository.close);
  });

  test(
    'creation requires an authenticated user before any SDK write',
    () async {
      auth.currentUser = null;
      parent.value = null;
      await expectLater(
        repository.saveFarm(farm),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(parent.reads, 0);
      expect(parent.writes, 0);
      expect(store.batches, 0);
    },
  );

  test(
    'Firestore listener preserves invalid legacy assignments for explicit repair but rejects saves',
    () async {
      final crop = farm.crops.first.copyWith(requiresIrrigation: true);
      final field = farm.fields.first.copyWith(
        currentCropId: crop.id,
        compatibleCropIds: [crop.id],
        cropHistory: [],
        irrigated: false,
      );
      final invalid = farm.copyWith(crops: [crop], fields: [field]);
      parent.value = {...parent.value!, 'data': invalid.toJson()};
      final received = <List<Farm>>[];
      final subscription = repository.watchFarms().listen(received.add);
      store.queries['farms']!.add(
        _QuerySnapshot([_QueryDocument(farm.id, parent.value!)]),
      );
      await Future<void>.delayed(Duration.zero);
      final editing = received.single.single;
      expect(editing.fields.single.currentCropId, crop.id);
      expect(editing.fields.single.irrigated, isFalse);
      await expectLater(
        repository.saveFarm(editing),
        throwsA(isA<DataValidationFailure>()),
      );
      await expectLater(
        repository.readFarm(farm.id),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(parent.writes, 0);
      final corrected = editing.copyWith(
        fields: [field.copyWith(irrigated: true)],
      );
      await repository.saveFarm(corrected);
      expect(
        (await repository.readFarm(farm.id)).fields.single.currentCropId,
        crop.id,
      );
      await subscription.cancel();
      await store.queries['farms']!.close();
    },
  );

  test(
    'Firestore legacy names normalize to IDs and persist only on explicit accepted save',
    () async {
      final crop = farm.crops.first;
      final field = farm.fields.first.copyWith(
        currentCropId: crop.id,
        compatibleCropIds: [crop.id],
        cropHistory: [crop.id],
        irrigated: true,
      );
      final data = farm.copyWith(crops: [crop], fields: [field]).toJson();
      final legacy = (data['fields'] as List).single as Map<String, dynamic>;
      legacy['currentCropId'] = crop.name;
      legacy['allowedCropIds'] = [crop.name];
      legacy.remove('compatibleCropIds');
      legacy['cropHistory'] = [crop.name];
      parent.value = {...parent.value!, 'data': data};
      final normalized = await repository.readFarm(farm.id);
      expect(parent.writes, 0);
      expect(normalized.fields.single.currentCropId, crop.id);
      await repository.saveFarm(normalized);
      final reopened = await repository.readFarm(farm.id);
      expect(reopened.fields.single.toJson(), field.toJson());
      final storedField =
          ((parent.value!['data'] as Map)['fields'] as List).single as Map;
      expect(storedField['currentCropId'], crop.id);
      expect(storedField['compatibleCropIds'], [crop.id]);
      expect(storedField.containsKey('allowedCropIds'), isFalse);
    },
  );

  test(
    'new farm and owner membership commit atomically before success',
    () async {
      parent.value = null;
      store.commitGate = Completer<void>();
      var completed = false;
      final save = repository.saveFarm(farm).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(parent.lastReadOptions?.source, Source.server);
      expect(store.batches, 1);
      expect(parent.value, isNull);
      expect(completed, isFalse);
      expect(repository.currentSyncStatus.hasPendingWrites, isTrue);

      store.commitGate!.complete();
      await save;
      final envelope = parent.value!;
      expect(envelope['ownerId'], 'owner');
      expect(envelope['data'], farm.toJson());
      expect(envelope['createdAt'], isA<FieldValue>());
      expect(envelope['updatedAt'], isA<FieldValue>());
      final member = store.document('farms/${farm.id}/members/owner').value!;
      expect(member['userId'], 'owner');
      expect(member['role'], 'owner');
      expect(member['createdAt'], isA<FieldValue>());
      expect(completed, isTrue);
      expect(repository.currentSyncStatus.hasPendingWrites, isFalse);
    },
  );

  test(
    'failed creation surfaces permission-denied and writes neither record',
    () async {
      parent.value = null;
      store.commitGate = Completer<void>();
      final failure = expectLater(
        repository.saveFarm(farm),
        throwsA(
          isA<PermissionFailure>().having(
            (error) => error.code,
            'Firebase code',
            'permission-denied',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      store.commitGate!.completeError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Rejected by rules',
        ),
      );
      await failure;
      expect(parent.value, isNull);
      expect(store.document('farms/${farm.id}/members/owner').value, isNull);
      expect(repository.currentSyncStatus.failure, isA<PermissionFailure>());
    },
  );

  test(
    'optimistic new farms are hidden until server acknowledgement',
    () async {
      final received = <List<Farm>>[];
      final subscription = repository.watchFarms().listen(received.add);
      final query = store.queries['farms']!;
      query.add(
        _QuerySnapshot([
          _QueryDocument(farm.id, parent.value!, pending: true),
        ], true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received.single, isEmpty);
      query.add(_QuerySnapshot([_QueryDocument(farm.id, parent.value!)]));
      await Future<void>.delayed(Duration.zero);
      expect(received.last.single.id, farm.id);
      await subscription.cancel();
      await query.close();
    },
  );

  test(
    'cached farms remain explicitly unconfirmed until a server snapshot',
    () async {
      final subscription = repository.watchFarms().listen((_) {});
      final query = store.queries['farms']!;
      final documents = [_QueryDocument(farm.id, parent.value!)];
      query.add(_QuerySnapshot(documents, false, true));
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentSyncStatus.isFromCache, isTrue);
      expect(repository.currentSyncStatus.message, contains('not confirmed'));
      query.add(_QuerySnapshot(documents));
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentSyncStatus.isFromCache, isFalse);
      expect(
        repository.currentSyncStatus.message,
        contains('confirmed by the cloud'),
      );
      await subscription.cancel();
      await query.close();
    },
  );

  test('pending edits retain the last confirmed farm until accepted', () async {
    final received = <List<Farm>>[];
    final subscription = repository.watchFarms().listen(received.add);
    final query = store.queries['farms']!;
    query.add(_QuerySnapshot([_QueryDocument(farm.id, parent.value!)]));
    await Future<void>.delayed(Duration.zero);
    final edited = farm.copyWith(name: 'Entered replacement name');
    final editedEnvelope = {...parent.value!, 'data': edited.toJson()};
    query.add(
      _QuerySnapshot([
        _QueryDocument(farm.id, editedEnvelope, pending: true),
      ], true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received.last.single.name, farm.name);
    query.add(_QuerySnapshot([_QueryDocument(farm.id, editedEnvelope)]));
    await Future<void>.delayed(Duration.zero);
    expect(received.last.single.name, edited.name);
    await subscription.cancel();
    await query.close();
  });

  test(
    'pending snapshots cannot be read or used as creation preflight',
    () async {
      parent.pending = true;
      await expectLater(
        repository.readFarm(farm.id),
        throwsA(
          isA<NetworkFailure>().having(
            (error) => error.code,
            'Firebase code',
            'write-pending',
          ),
        ),
      );
      await expectLater(
        repository.saveFarm(farm),
        throwsA(isA<NetworkFailure>()),
      );
      expect(parent.writes, 0);
      expect(store.batches, 0);
    },
  );

  test(
    'Firestore entity save validates harvest and replaces omitted fields',
    () async {
      final document = store.document('farms/${farm.id}/harvestBatches/batch');
      await expectLater(
        repository.saveEntity(
          farm.id,
          EntityKind.harvestBatches,
          const StoredEntity(id: 'batch', data: {'crop': ''}),
        ),
        throwsA(isA<DataValidationFailure>()),
      );
      expect(document.writes, 0);
      await repository.saveEntity(
        farm.id,
        EntityKind.harvestBatches,
        const StoredEntity(
          id: 'batch',
          data: {'crop': 'Crop', 'notes': 'Entered notes'},
        ),
      );
      final createdAt = document.value!['createdAt'];
      await repository.saveEntity(
        farm.id,
        EntityKind.harvestBatches,
        const StoredEntity(id: 'batch', data: {'crop': 'Changed crop'}),
      );
      expect(document.value!['data'], {'crop': 'Changed crop'});
      expect(document.value!['createdAt'], same(createdAt));
    },
  );

  test(
    'cached farm cannot be decoded after sign-out or by another account',
    () async {
      expect((await repository.readFarm(farm.id)).id, farm.id);
      auth.currentUser = null;
      await expectLater(
        repository.readFarm(farm.id),
        throwsA(isA<AuthenticationFailure>()),
      );
      auth.currentUser = _Account('other');
      await expectLater(
        repository.readFarm(farm.id),
        throwsA(isA<PermissionFailure>()),
      );
      await expectLater(
        repository.saveFarm(farm),
        throwsA(isA<PermissionFailure>()),
      );
      expect(parent.writes, 0);
    },
  );

  test('account switch during cached read cannot expose its result', () async {
    parent.readGate = Completer<void>();
    final read = repository.readFarm(farm.id);
    auth.currentUser = _Account('other');
    parent.readGate!.complete();
    await expectLater(read, throwsA(isA<AuthenticationFailure>()));
  });

  test(
    'account switch during save preflight cannot queue a farm write',
    () async {
      parent.readGate = Completer<void>();
      final save = repository.saveFarm(farm);
      auth.currentUser = _Account('other');
      parent.readGate!.complete();
      await expectLater(save, throwsA(isA<AuthenticationFailure>()));
      expect(parent.writes, 0);
    },
  );

  test(
    'entity reads, saves, and deletes require ownership of cached parent',
    () async {
      auth.currentUser = _Account('other');
      await expectLater(
        repository.watchEntities(farm.id, EntityKind.scenarios).first,
        throwsA(isA<PermissionFailure>()),
      );
      await expectLater(
        repository.saveEntity(
          farm.id,
          EntityKind.scenarios,
          const StoredEntity(id: 'private', data: {'name': 'private'}),
        ),
        throwsA(isA<PermissionFailure>()),
      );
      await expectLater(
        repository.deleteEntity(farm.id, EntityKind.scenarios, 'private'),
        throwsA(isA<PermissionFailure>()),
      );
      expect(store.queries, isEmpty);
      expect(store.document('farms/${farm.id}/scenarios/private').writes, 0);
    },
  );

  test('entity save rechecks account after child cache read', () async {
    final child = store.document('farms/${farm.id}/scenarios/private')
      ..readGate = Completer<void>();
    final save = repository.saveEntity(
      farm.id,
      EntityKind.scenarios,
      const StoredEntity(id: 'private', data: {'name': 'private'}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(child.reads, 1);
    auth.currentUser = _Account('other');
    child.readGate!.complete();
    await expectLater(save, throwsA(isA<AuthenticationFailure>()));
    expect(child.writes, 0);
  });

  test(
    'existing entity subscription rejects snapshots after account switch',
    () async {
      final received = <List<StoredEntity>>[];
      final failure = Completer<Object>();
      final subscription = repository
          .watchEntities(farm.id, EntityKind.scenarios)
          .listen(
            received.add,
            onError: (Object error) => failure.complete(error),
          );
      await Future<void>.delayed(Duration.zero);
      final query = store.queries['farms/${farm.id}/scenarios']!;
      query.add(_QuerySnapshot());
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      auth.currentUser = _Account('other');
      query.add(_QuerySnapshot());
      expect(await failure.future, isA<AuthenticationFailure>());
      expect(received, hasLength(1));
      await subscription.cancel();
      await query.close();
    },
  );

  test(
    'privacy settings guard rejects stale caller before any write',
    () async {
      final settings = FirestoreSettingsRepository(store, auth);
      auth.currentUser = _Account('other');
      await expectLater(
        settings.save(
          const UserSettings(analyticsConsent: true),
          expectedUid: 'owner',
        ),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(store.documents.keys, isNot(contains('users/other')));
      expect(store.documents.keys, isNot(contains('users/owner')));
    },
  );

  test(
    'privacy writes share visible bounded synchronization with farm writes',
    () async {
      final synchronization = WriteSynchronization(
        acknowledgementWait: Duration.zero,
      );
      final farms = FirestoreFarmRepository(
        store,
        auth,
        _Functions(),
        synchronization: synchronization,
      );
      final settings = FirestoreSettingsRepository(
        store,
        auth,
        synchronization: synchronization,
      );
      parent.writeGate = Completer<void>();
      final account = store.document('users/owner')
        ..writeGate = Completer<void>();
      await Future.wait([
        expectLater(farms.saveFarm(farm), throwsA(isA<NetworkFailure>())),
        expectLater(
          settings.save(const UserSettings(), expectedUid: 'owner'),
          throwsA(isA<NetworkFailure>()),
        ),
      ]);
      expect(farms.currentSyncStatus.hasPendingWrites, isTrue);
      parent.writeGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(farms.currentSyncStatus.hasPendingWrites, isTrue);
      final done = farms.syncStatus.firstWhere(
        (state) => !state.hasPendingWrites,
      );
      account.writeGate!.complete();
      expect((await done).failure, isNull);
      await farms.close();
    },
  );
}
