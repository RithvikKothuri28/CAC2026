import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/farm_domain.dart';
import '../repositories/data_codec.dart';
import '../repositories/farm_repository.dart';
import 'firebase_development_logger.dart';
import 'firebase_failure.dart';
import 'write_synchronization.dart';

/// Production persistence. Firestore's mobile disk cache and pending write
/// queue remain authoritative offline; there is no sample-data fallback.
class FirestoreFarmRepository implements FarmRepository {
  FirestoreFarmRepository(
    this._firestore,
    this._auth,
    this._functions, {
    WriteSynchronization? synchronization,
    bool developmentLogging = false,
  }) : _synchronization = synchronization ?? WriteSynchronization(),
       _logger = FirebaseDevelopmentLogger(enabled: developmentLogging);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final Map<String, Map<String, dynamic>> _knownEnvelopes = {};
  final Map<String, Farm> _confirmedFarms = {};
  final WriteSynchronization _synchronization;
  final FirebaseDevelopmentLogger _logger;
  Stream<FarmSyncStatus> get syncStatus => _synchronization.status;
  FarmSyncStatus get currentSyncStatus => _synchronization.current;

  String get _uid =>
      _auth.currentUser?.uid ??
      (throw const AuthenticationFailure('Sign in to access your farms.'));
  CollectionReference<Map<String, dynamic>> get _farms =>
      _firestore.collection('farms');

  void _requireAccount(String uid) {
    if (_uid != uid) {
      throw const AuthenticationFailure(
        'Account changed before the farm operation could complete.',
      );
    }
  }

  void _requireOwner(Map<String, dynamic> envelope, String uid) {
    _requireAccount(uid);
    if (envelope['ownerId'] != uid) {
      throw const PermissionFailure(
        'This farm belongs to another account. Sign in with its owner account.',
      );
    }
  }

  Farm _decode(
    DocumentSnapshot<Map<String, dynamic>> document,
    String uid, {
    bool forEditing = false,
  }) {
    _requireAccount(uid);
    final envelope = document.data();
    if (envelope == null) {
      throw const RepositoryUnavailableFailure(
        'The requested farm does not exist.',
      );
    }
    // Firestore can serve a previous account's disk cache without evaluating
    // server rules. Check ownership before decoding or exposing that cache.
    _requireOwner(envelope, uid);
    if (envelope['schemaVersion'] != 1) {
      throw const DataValidationFailure(
        'This farm uses an unsupported database version. Update FarmTwin.',
      );
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw const DataValidationFailure('The farm record is incomplete.');
    }
    final values = {...Map<String, dynamic>.from(data), 'id': document.id};
    final farm = forEditing
        ? FarmDataCodec.decodeFarmForEditing(values)
        : FarmDataCodec.decodeFarm(values);
    _knownEnvelopes[document.id] = envelope;
    _confirmedFarms[document.id] = farm;
    return farm;
  }

  @override
  Stream<List<Farm>> watchFarms() {
    try {
      final uid = _uid;
      return _farms
          .where('ownerId', isEqualTo: uid)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            _requireAccount(uid);
            _synchronization.updateMetadata(
              hasPendingWrites: snapshot.metadata.hasPendingWrites,
              isFromCache: snapshot.metadata.isFromCache,
            );
            final visible = <Farm>[];
            for (final document in snapshot.docs) {
              _requireOwner(document.data(), uid);
              if (document.metadata.hasPendingWrites) {
                // Firestore emits optimistic local snapshots before acceptance.
                // Keep the last confirmed version of edits and withhold new
                // farms entirely until the server acknowledges the write.
                final confirmed = _confirmedFarms[document.id];
                if (confirmed != null) visible.add(confirmed);
              } else {
                // Preserve legacy assignments for explicit correction in My farm.
                // Workspace readiness and all saves/calculations remain strict.
                visible.add(_decode(document, uid, forEditing: true));
              }
            }
            final present = snapshot.docs
                .map((document) => document.id)
                .toSet();
            _confirmedFarms.removeWhere((id, _) => !present.contains(id));
            _knownEnvelopes.removeWhere((id, _) => !present.contains(id));
            return visible;
          })
          .handleError((Object error) => throw firebaseFailure(error));
    } on Object catch (error) {
      return Stream.error(firebaseFailure(error));
    }
  }

  @override
  Future<Farm> readFarm(String id) => firebaseGuard(() async {
    final uid = _uid;
    FarmDataCodec.validateId(id);
    final snapshot = await _farms
        .doc(id)
        .get(const GetOptions(source: Source.server));
    _requireConfirmed(snapshot);
    return _decode(snapshot, uid);
  });

  @override
  Future<void> saveFarm(Farm farm) => firebaseGuard(() async {
    FarmDataCodec.validateId(farm.id);
    final uid = _auth.currentUser?.uid;
    final path = 'farms/${farm.id}';
    _log('save requested', uid: uid, path: path);
    try {
      await _saveFarm(farm);
    } on Object catch (error) {
      // Include authentication, validation, and server-read failures that occur
      // before a write can be submitted, as well as rejected writes.
      _log('save failure', uid: uid, path: path, error: error);
      rethrow;
    }
  });

  Future<void> _saveFarm(Farm farm) async {
    final uid = _uid;
    final data = FarmDataCodec.encodeFarm(farm);
    final reference = _farms.doc(farm.id);
    // Only previously confirmed envelopes can skip a fresh server read. Cache
    // misses are not evidence that a record does not exist on the server.
    var existing = _knownEnvelopes[farm.id];
    if (existing == null) {
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      _requireConfirmed(snapshot);
      existing = snapshot.data();
    }
    _requireAccount(uid);
    if (existing != null) {
      _requireOwner(existing, uid);
      await _write(
        uid,
        reference.path,
        () => reference.update({
          'name': farm.name,
          'schemaVersion': 1,
          'data': data,
          'source': farm.provenance.source.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    } else {
      final batch = _firestore.batch();
      batch.set(reference, {
        'ownerId': uid,
        'name': farm.name,
        'schemaVersion': 1,
        'data': data,
        'source': farm.provenance.source.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(reference.collection('members').doc(uid), {
        'userId': uid,
        'role': 'owner',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _write(uid, reference.path, batch.commit);
    }
    _requireAccount(uid);
    // No optimistic cache mutation is allowed before the SDK future resolves.
    _knownEnvelopes[farm.id] = {'ownerId': uid};
    _confirmedFarms[farm.id] = farm;
  }

  void _log(String event, {String? uid, required String path, Object? error}) =>
      _logger.event(
        event,
        uid: uid,
        projectId: _logger.enabled ? _firestore.app.options.projectId : null,
        path: path,
        error: error,
      );

  void _requireConfirmed(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.metadata.hasPendingWrites) {
      throw const NetworkFailure(
        'This farm still has a write awaiting Firestore confirmation. '
        'Reconnect and wait before retrying.',
        code: 'write-pending',
      );
    }
  }

  Future<void> _write(
    String uid,
    String path,
    Future<void> Function() operation,
  ) async {
    void log(String event, {Object? error}) =>
        _log(event, uid: uid, path: path, error: error);
    log('write start');
    final write = Future<void>.sync(operation).then<void>(
      (_) => log('write success (server accepted)'),
      onError: (Object error, StackTrace stack) {
        log('write failure', error: error);
        Error.throwWithStackTrace(error, stack);
      },
    );
    try {
      await _synchronization.track(write);
    } on NetworkFailure catch (error) {
      if (error.code == 'write-pending') log('write pending', error: error);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _cachedData(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      return (await reference.get(
        const GetOptions(source: Source.cache),
      )).data();
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable') return null;
      rethrow;
    }
  }

  @override
  Future<void> deleteFarm(String id) => firebaseGuard(() async {
    final uid = _uid;
    FarmDataCodec.validateId(id);
    await _requireOwnedFarm(id, uid);
    _requireAccount(uid);
    await _functions.httpsCallable('deleteFarm').call<void>({'farmId': id});
    _knownEnvelopes.remove(id);
    _confirmedFarms.remove(id);
  });

  CollectionReference<Map<String, dynamic>> _entities(
    String farmId,
    EntityKind kind,
  ) {
    FarmDataCodec.validateId(farmId);
    return _farms.doc(farmId).collection(kind.name);
  }

  Future<void> _requireOwnedFarm(String farmId, String uid) async {
    FarmDataCodec.validateId(farmId);
    final envelope =
        _knownEnvelopes[farmId] ?? (await _farms.doc(farmId).get()).data();
    _requireAccount(uid);
    if (envelope == null) {
      throw const RepositoryUnavailableFailure(
        'The requested farm does not exist.',
      );
    }
    _requireOwner(envelope, uid);
    _knownEnvelopes[farmId] = envelope;
  }

  @override
  Stream<List<StoredEntity>> watchEntities(
    String farmId,
    EntityKind kind,
  ) async* {
    try {
      final uid = _uid;
      await _requireOwnedFarm(farmId, uid);
      _requireAccount(uid);
      yield* _entities(farmId, kind)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            _requireAccount(uid);
            return snapshot.docs
                .map((document) {
                  final json = document.data();
                  if (json['schemaVersion'] != 1 || json['data'] is! Map) {
                    throw const DataValidationFailure(
                      'A saved record has an unsupported version or invalid data.',
                    );
                  }
                  return StoredEntity(
                    id: document.id,
                    data: Map<String, dynamic>.from(json['data'] as Map),
                  );
                })
                .toList(growable: false);
          })
          .handleError((Object error) => throw firebaseFailure(error));
    } on Object catch (error) {
      throw firebaseFailure(error);
    }
  }

  @override
  Future<void> saveEntity(
    String farmId,
    EntityKind kind,
    StoredEntity entity,
  ) => firebaseGuard(() async {
    final uid = _uid;
    FarmDataCodec.validateId(entity.id);
    final data = FarmDataCodec.validatePayload(entity.data);
    if (kind == EntityKind.harvestBatches) {
      FarmDataCodec.validateHarvestBatch(data);
    }
    final reference = _entities(farmId, kind).doc(entity.id);
    await _requireOwnedFarm(farmId, uid);
    final current = await _cachedData(reference);
    _requireAccount(uid);
    await _synchronization.track(
      current == null
          ? reference.set({
              'schemaVersion': 1,
              'data': data,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            })
          : reference.update({
              'schemaVersion': 1,
              // update replaces the data map, including removal of omitted
              // fields, while preserving a still-pending createdAt transform.
              'data': data,
              'updatedAt': FieldValue.serverTimestamp(),
            }),
    );
  });

  @override
  Future<void> deleteEntity(String farmId, EntityKind kind, String id) =>
      firebaseGuard(() async {
        final uid = _uid;
        FarmDataCodec.validateId(id);
        await _requireOwnedFarm(farmId, uid);
        _requireAccount(uid);
        await _synchronization.track(_entities(farmId, kind).doc(id).delete());
      });

  @override
  Future<void> close() async {
    _knownEnvelopes.clear();
    _confirmedFarms.clear();
    await _synchronization.close();
  }
}
