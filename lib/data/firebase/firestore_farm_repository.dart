import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/farm_domain.dart';
import '../repositories/data_codec.dart';
import '../repositories/farm_repository.dart';
import 'firebase_failure.dart';
import 'write_synchronization.dart';

/// Production persistence. Firestore's mobile disk cache and pending write
/// queue remain authoritative offline; there is no sample-data fallback.
class FirestoreFarmRepository implements FarmRepository {
  FirestoreFarmRepository(this._firestore, this._auth, this._functions);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final Map<String, Map<String, dynamic>> _knownEnvelopes = {};
  final _synchronization = WriteSynchronization();
  Stream<FarmSyncStatus> get syncStatus => _synchronization.status;
  FarmSyncStatus get currentSyncStatus => _synchronization.current;

  String get _uid =>
      _auth.currentUser?.uid ??
      (throw const AuthenticationFailure('Sign in to access your farms.'));
  CollectionReference<Map<String, dynamic>> get _farms =>
      _firestore.collection('farms');

  Farm _decode(DocumentSnapshot<Map<String, dynamic>> document) {
    final envelope = document.data();
    if (envelope == null) {
      throw const RepositoryUnavailableFailure(
        'The requested farm does not exist.',
      );
    }
    if (envelope['schemaVersion'] != 1) {
      throw const DataValidationFailure(
        'This farm uses an unsupported database version. Update FarmTwin.',
      );
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw const DataValidationFailure('The farm record is incomplete.');
    }
    final farm = FarmDataCodec.decodeFarm({
      ...Map<String, dynamic>.from(data),
      'id': document.id,
    });
    _knownEnvelopes[document.id] = envelope;
    return farm;
  }

  @override
  Stream<List<Farm>> watchFarms() {
    try {
      return _farms
          .where('ownerId', isEqualTo: _uid)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            _synchronization.updateMetadata(
              hasPendingWrites: snapshot.metadata.hasPendingWrites,
              isFromCache: snapshot.metadata.isFromCache,
            );
            return snapshot.docs.map(_decode).toList(growable: false);
          })
          .handleError((Object error) => throw firebaseFailure(error));
    } on Object catch (error) {
      return Stream.error(firebaseFailure(error));
    }
  }

  @override
  Future<Farm> readFarm(String id) => firebaseGuard(() async {
    FarmDataCodec.validateId(id);
    return _decode(await _farms.doc(id).get());
  });

  @override
  Future<void> saveFarm(Farm farm) => firebaseGuard(() async {
    final data = FarmDataCodec.encodeFarm(farm);
    final reference = _farms.doc(farm.id);
    final uid = _uid;
    // Already-loaded farm edits do not require a round trip before queueing.
    var existing = _knownEnvelopes[farm.id];
    if (existing == null) {
      existing = await _cachedData(reference);
      if (existing != null) _knownEnvelopes[farm.id] = existing;
    }
    if (existing != null) {
      await _synchronization.track(
        reference.update({
          'name': farm.name,
          'schemaVersion': 1,
          'data': data,
          'source': farm.provenance.source.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    } else {
      final write = reference.set({
        'ownerId': uid,
        'name': farm.name,
        'schemaVersion': 1,
        'data': data,
        'source': farm.provenance.source.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _knownEnvelopes[farm.id] = {'ownerId': uid};
      await _synchronization.track(write);
    }
  });

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
    FarmDataCodec.validateId(id);
    await _functions.httpsCallable('deleteFarm').call<void>({'farmId': id});
    _knownEnvelopes.remove(id);
  });

  CollectionReference<Map<String, dynamic>> _entities(
    String farmId,
    EntityKind kind,
  ) {
    FarmDataCodec.validateId(farmId);
    return _farms.doc(farmId).collection(kind.name);
  }

  @override
  Stream<List<StoredEntity>> watchEntities(String farmId, EntityKind kind) {
    try {
      return _entities(farmId, kind)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
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
      return Stream.error(firebaseFailure(error));
    }
  }

  @override
  Future<void> saveEntity(
    String farmId,
    EntityKind kind,
    StoredEntity entity,
  ) => firebaseGuard(() async {
    FarmDataCodec.validateId(entity.id);
    final data = FarmDataCodec.validatePayload(entity.data);
    if (kind == EntityKind.harvestBatches)
      FarmDataCodec.validateHarvestBatch(data);
    final reference = _entities(farmId, kind).doc(entity.id);
    final current = await _cachedData(reference);
    await _synchronization.track(
      reference.set({
        'schemaVersion': 1,
        'data': data,
        'createdAt': current?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  });

  @override
  Future<void> deleteEntity(String farmId, EntityKind kind, String id) =>
      firebaseGuard(() async {
        FarmDataCodec.validateId(id);
        await _synchronization.track(_entities(farmId, kind).doc(id).delete());
      });

  @override
  Future<void> close() async {
    _knownEnvelopes.clear();
    await _synchronization.close();
  }
}
