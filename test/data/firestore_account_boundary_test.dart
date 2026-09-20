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

// Controlled SDK test doubles; these are never application implementations.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
}

class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
}

/// Keeps cache delivery and write acknowledgements under test control. These
/// tests intentionally return cached records regardless of Firebase Auth, just
/// as the SDK can do while offline; the adapter must enforce its own boundary.
class _Firestore extends Fake implements FirebaseFirestore {
  final documents = <String, _Document>{};
  final queries =
      <String, StreamController<QuerySnapshot<Map<String, dynamic>>>>{};
  _Document document(String path) =>
      documents.putIfAbsent(path, () => _Document(this, path));
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
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
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    reads++;
    if (readGate != null) await readGate!.future;
    return _Snapshot(path.split('/').last, value);
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
      jsonDecode(File('assets/sample/sample_farm.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    parent = store.document('farms/${farm.id}')
      ..value = {'ownerId': 'owner', 'schemaVersion': 1, 'data': farm.toJson()};
    addTearDown(repository.close);
  });

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
        farms.saveFarm(farm),
        settings.save(const UserSettings(), expectedUid: 'owner'),
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
