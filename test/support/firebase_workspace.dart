import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:farmtwin/app/config/app_config.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:flutter_test/flutter_test.dart';

Farm fixtureFarm() => Farm.fromJson(
  jsonDecode(File('test/fixtures/farm.json').readAsStringSync())
      as Map<String, dynamic>,
);

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
  @override
  String get email => '$uid@example.test';
}

class TestAuth extends Fake implements FirebaseAuthRepository {
  TestAuth({bool signedIn = true}) {
    currentUser = signedIn ? TestUser('owner') : null;
  }
  final _changes = StreamController<User?>.broadcast();
  @override
  User? currentUser;
  @override
  Stream<User?> get authStateChanges async* {
    yield currentUser;
    yield* _changes.stream;
  }

  void setUser(User? user) {
    currentUser = user;
    _changes.add(user);
  }

  @override
  Future<void> signOut() async => setUser(null);
  Future<void> close() => _changes.close();
}

/// Test-only SDK boundary. Production providers always bind the concrete cloud
/// repository; these tests control acknowledgement timing without network I/O.
class TestFarms extends Fake implements FirestoreFarmRepository {
  TestFarms([List<Farm> initial = const []]) : values = initial;
  List<Farm> values;
  final writes = <Farm>[];
  Completer<void>? acknowledgement;
  Object? saveFailure;
  final _changes = StreamController<List<Farm>>.broadcast();
  @override
  FarmSyncStatus get currentSyncStatus =>
      const FarmSyncStatus(isFromCache: false);
  @override
  Stream<FarmSyncStatus> get syncStatus => Stream.value(currentSyncStatus);
  @override
  Stream<List<Farm>> watchFarms() async* {
    yield values;
    yield* _changes.stream;
  }

  @override
  Future<void> saveFarm(Farm farm) async {
    writes.add(farm);
    await acknowledgement?.future;
    if (saveFailure != null) throw saveFailure!;
    values = [...values.where((item) => item.id != farm.id), farm];
    _changes.add(values);
  }

  @override
  Stream<List<StoredEntity>> watchEntities(String farmId, EntityKind kind) =>
      Stream.value(const []);
  @override
  Future<void> close() => _changes.close();
}

class TestSettings extends Fake implements FirestoreSettingsRepository {
  @override
  Future<UserSettings> read() async => const UserSettings();
}

class TestPrivacy extends Fake implements FirebasePrivacyService {
  @override
  UserSettings get current => const UserSettings();
  @override
  Future<void> bindAccount(
    String? uid,
    Future<UserSettings> Function() readRemote,
  ) async {}
}

class TestCloud extends Fake implements FirebaseServices {
  TestCloud({TestAuth? auth, TestFarms? farms})
    : auth = auth ?? TestAuth(),
      farms = farms ?? TestFarms();
  @override
  final TestAuth auth;
  @override
  final TestFarms farms;
  @override
  final TestSettings settings = TestSettings();
  @override
  final TestPrivacy privacy = TestPrivacy();
  @override
  FeatureConfig get features => const FeatureConfig();
  Future<void> close() async {
    await auth.close();
    await farms.close();
  }
}
