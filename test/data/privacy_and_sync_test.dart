import 'dart:async';
import 'dart:convert';

import 'package:farmtwin/data/data.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlledAnalytics extends Fake implements FirebaseAnalytics {
  final states = <bool>[];
  Completer<void>? pauseNextEnable;

  @override
  Future<void> setAnalyticsCollectionEnabled(bool enabled) async {
    states.add(enabled);
    if (enabled && pauseNextEnable != null) {
      final pause = pauseNextEnable!;
      pauseNextEnable = null;
      await pause.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const optedIn = UserSettings(
    analyticsConsent: true,
    crashReportingConsent: true,
    cloudAssistantConsent: true,
  );

  test(
    'optional analytics SDK initializes only after consent and disables on sign-out',
    () async {
      final analytics = ControlledAnalytics();
      var created = 0;
      final privacy = FirebasePrivacyService(
        preferences: await SharedPreferences.getInstance(),
        analyticsFactory: () {
          created++;
          return analytics;
        },
      );
      await privacy.apply(const UserSettings());
      await privacy.bindAccount('owner', () async => const UserSettings());
      expect(created, 0);
      expect(analytics.states, isEmpty);
      await privacy.apply(optedIn);
      expect(created, 1);
      expect(analytics.states, [true]);
      await privacy.bindAccount(null, () async => const UserSettings());
      expect(created, 1);
      expect(analytics.states.last, isFalse);
    },
  );

  test(
    'a previous account remote response cannot enable the active account',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final privacy = FirebasePrivacyService(
        preferences: preferences,
        allowCollection: false,
      );
      final firstRemote = Completer<UserSettings>();
      final firstReadStarted = Completer<void>();
      final firstBind = privacy.bindAccount('first', () {
        firstReadStarted.complete();
        return firstRemote.future;
      });
      await firstReadStarted.future;
      await privacy.bindAccount('second', () async => const UserSettings());
      firstRemote.complete(optedIn);
      await firstBind;
      expect(privacy.current.toJson(), const UserSettings().toJson());
      expect(
        jsonDecode(
          preferences.getString('${FirebasePrivacyService.storageKey}.second')!,
        ),
        const UserSettings().toJson(),
      );
    },
  );

  test(
    'a previous account failure cannot restore its cache or emit an obsolete failure',
    () async {
      SharedPreferences.setMockInitialValues({
        '${FirebasePrivacyService.storageKey}.first': jsonEncode(
          optedIn.toJson(),
        ),
      });
      final privacy = FirebasePrivacyService(
        preferences: await SharedPreferences.getInstance(),
        allowCollection: false,
      );
      final remote = Completer<UserSettings>();
      final started = Completer<void>();
      final first = privacy.bindAccount('first', () {
        started.complete();
        return remote.future;
      });
      await started.future;
      await privacy.bindAccount('second', () async => const UserSettings());
      remote.completeError(const NetworkFailure('Offline'));
      await first;
      expect(privacy.current.analyticsConsent, isFalse);
      expect(privacy.current.cloudAssistantConsent, isFalse);
    },
  );

  test(
    'same-account offline preferences survive temporary disable and reopen',
    () async {
      final key = '${FirebasePrivacyService.storageKey}.farmer';
      SharedPreferences.setMockInitialValues({
        key: jsonEncode(optedIn.toJson()),
      });
      final preferences = await SharedPreferences.getInstance();
      final privacy = FirebasePrivacyService(
        preferences: preferences,
        allowCollection: false,
      );
      final remote = Completer<UserSettings>();
      final started = Completer<void>();
      final bind = privacy.bindAccount('farmer', () {
        started.complete();
        return remote.future;
      });
      await started.future;
      expect(privacy.current.analyticsConsent, isFalse);
      // A process death while waiting cannot erase the previously explicit consent.
      expect(jsonDecode(preferences.getString(key)!), optedIn.toJson());
      remote.completeError(const NetworkFailure('Offline'));
      await expectLater(bind, throwsA(isA<NetworkFailure>()));
      expect(privacy.current.toJson(), optedIn.toJson());
      final reopened = FirebasePrivacyService(
        preferences: preferences,
        allowCollection: false,
      );
      await expectLater(
        reopened.bindAccount(
          'farmer',
          () async => throw const NetworkFailure('Offline'),
        ),
        throwsA(isA<NetworkFailure>()),
      );
      expect(reopened.current.toJson(), optedIn.toJson());
      await reopened.bindAccount(
        null,
        () async => throw StateError('Signed out must not fetch'),
      );
      expect(reopened.current.analyticsConsent, isFalse);
      expect(jsonDecode(preferences.getString(key)!), optedIn.toJson());
    },
  );

  test(
    'permission failures do not activate cached consent; corrupt cache is typed',
    () async {
      final key = '${FirebasePrivacyService.storageKey}.farmer';
      SharedPreferences.setMockInitialValues({
        key: jsonEncode(optedIn.toJson()),
      });
      final preferences = await SharedPreferences.getInstance();
      final privacy = FirebasePrivacyService(
        preferences: preferences,
        allowCollection: false,
      );
      await expectLater(
        privacy.bindAccount(
          'farmer',
          () async => throw const PermissionFailure('Denied'),
        ),
        throwsA(isA<PermissionFailure>()),
      );
      expect(privacy.current.analyticsConsent, isFalse);
      await preferences.setString(key, 'broken-json');
      await expectLater(
        privacy.bindAccount(
          'farmer',
          () async => throw const NetworkFailure('Offline'),
        ),
        throwsA(isA<StorageFailure>()),
      );
      expect(privacy.current.analyticsConsent, isFalse);
      expect(preferences.getString(key), 'broken-json');
    },
  );

  test(
    'explicit privacy change wins over an earlier pending server read',
    () async {
      final privacy = FirebasePrivacyService(
        preferences: await SharedPreferences.getInstance(),
        allowCollection: false,
      );
      final remote = Completer<UserSettings>();
      final started = Completer<void>();
      final bind = privacy.bindAccount('farmer', () {
        started.complete();
        return remote.future;
      });
      await started.future;
      await privacy.apply(const UserSettings(cloudAssistantConsent: true));
      remote.complete(optedIn);
      await bind;
      expect(privacy.current.cloudAssistantConsent, isTrue);
      expect(privacy.current.analyticsConsent, isFalse);
      expect(privacy.current.crashReportingConsent, isFalse);
    },
  );

  test(
    'a slow SDK enable cannot commit old consent after account switch',
    () async {
      final analytics = ControlledAnalytics();
      final privacy = FirebasePrivacyService(
        preferences: await SharedPreferences.getInstance(),
        analytics: analytics,
      );
      await privacy.bindAccount('first', () async => const UserSettings());
      final releaseEnable = Completer<void>();
      analytics.pauseNextEnable = releaseEnable;
      final firstApply = privacy.apply(optedIn);
      await Future<void>.delayed(Duration.zero);
      expect(analytics.states.last, isTrue);
      final secondBind = privacy.bindAccount(
        'second',
        () async => const UserSettings(),
      );
      expect(privacy.current.analyticsConsent, isFalse);
      releaseEnable.complete();
      await Future.wait([firstApply, secondBind]);
      expect(privacy.current.toJson(), const UserSettings().toJson());
      expect(analytics.states.last, isFalse);
    },
  );

  test(
    'write wait expires as queued, then publishes actual acknowledgement',
    () async {
      final synchronization = WriteSynchronization(
        acknowledgementWait: Duration.zero,
      );
      final write = Completer<void>();
      await synchronization.track(write.future);
      expect(synchronization.current.hasPendingWrites, isTrue);
      expect(synchronization.current.failure, isNull);
      expect(synchronization.current.message, contains('queued'));
      final acknowledged = synchronization.status.firstWhere(
        (state) => !state.hasPendingWrites,
      );
      write.complete();
      expect((await acknowledged).failure, isNull);
      synchronization.updateMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      );
      expect(
        synchronization.current.message,
        contains('confirmed by the cloud'),
      );
      await synchronization.close();
    },
  );

  test(
    'late write rejection remains visible without an unhandled asynchronous exception',
    () async {
      final synchronization = WriteSynchronization(
        acknowledgementWait: Duration.zero,
      );
      final write = Completer<void>();
      await synchronization.track(write.future);
      final rejection = synchronization.status.firstWhere(
        (state) => state.failure != null,
      );
      write.completeError(const PermissionFailure('Write rejected by rules'));
      final state = await rejection;
      expect(state.failure, isA<PermissionFailure>());
      expect(state.hasPendingWrites, isFalse);
      expect(state.message, 'Write rejected by rules');
      await synchronization.close();
    },
  );

  test(
    'immediate write failure is typed and concurrent writes remain pending independently',
    () async {
      final synchronization = WriteSynchronization(
        acknowledgementWait: Duration.zero,
      );
      await expectLater(
        synchronization.track(
          Future<void>.error(const PermissionFailure('Denied')),
        ),
        throwsA(isA<PermissionFailure>()),
      );
      final first = Completer<void>();
      final second = Completer<void>();
      await Future.wait([
        synchronization.track(first.future),
        synchronization.track(second.future),
      ]);
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(synchronization.current.hasPendingWrites, isTrue);
      second.complete();
      await synchronization.status.firstWhere(
        (state) => !state.hasPendingWrites,
      );
      await synchronization.close();
    },
  );
}
