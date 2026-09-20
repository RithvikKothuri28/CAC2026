import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_failure.dart';
import 'firebase_failure.dart';
import 'user_settings.dart';

class FirebasePrivacyService {
  FirebasePrivacyService({
    required SharedPreferences preferences,
    FirebaseAnalytics? analytics,
    FirebaseAnalytics Function()? analyticsFactory,
    FirebaseCrashlytics? crashlytics,
    this.allowCollection = true,
  }) : _preferences = preferences,
       _analytics = analytics,
       _analyticsFactory = analyticsFactory,
       _crashlytics = crashlytics;
  final SharedPreferences _preferences;
  FirebaseAnalytics? _analytics;
  final FirebaseAnalytics Function()? _analyticsFactory;
  final FirebaseCrashlytics? _crashlytics;
  final bool allowCollection;
  static const storageKey = 'farmtwin.privacy.v1';
  String _activeKey = storageKey;
  int _accountEpoch = 0;
  int _choiceEpoch = 0;
  Future<void> _pending = Future.value();
  UserSettings _current = const UserSettings();
  UserSettings get current => _current;

  Future<void> bindAccount(
    String? uid,
    Future<UserSettings> Function() readRemote,
  ) async {
    final epoch = ++_accountEpoch;
    _activeKey = uid == null ? storageKey : '$storageKey.$uid';
    final cached = uid == null ? null : _preferences.getString(_activeKey);
    final choiceEpoch = _choiceEpoch;
    _current = const UserSettings();
    // Disable collection while identity is changing, without erasing this
    // account's explicitly saved offline preferences.
    await _apply(const UserSettings(), persist: false);
    if (uid == null || epoch != _accountEpoch) return;
    try {
      final settings = await readRemote().timeout(const Duration(seconds: 5));
      if (epoch == _accountEpoch && choiceEpoch == _choiceEpoch) {
        await _apply(settings, persist: true);
      }
    } on Object catch (error) {
      if (epoch != _accountEpoch || choiceEpoch != _choiceEpoch) return;
      final failure = firebaseFailure(error);
      if (cached != null && failure is NetworkFailure) {
        try {
          final saved = UserSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(cached) as Map),
          );
          await _apply(saved, persist: false);
        } on AppFailure {
          rethrow;
        } on Object catch (cacheError) {
          throw StorageFailure(
            'Saved privacy preferences could not be read. Optional data collection is disabled.',
            cause: cacheError,
          );
        }
      }
      throw failure;
    }
  }

  Future<void> restore() async {
    final stored = _preferences.getString(_activeKey);
    if (stored == null) return apply(const UserSettings());
    try {
      await apply(
        UserSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(stored) as Map),
        ),
      );
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      await apply(const UserSettings());
      throw StorageFailure(
        'Saved privacy preferences could not be read. Optional data collection is disabled.',
        cause: error,
      );
    }
  }

  Future<void> apply(UserSettings settings) {
    _choiceEpoch++;
    return _apply(settings, persist: true);
  }

  Future<void> _apply(UserSettings settings, {required bool persist}) {
    final epoch = _accountEpoch;
    final key = _activeKey;
    final result = _pending.then(
      (_) => firebaseGuard(() async {
        if (epoch != _accountEpoch) return;
        final analyticsEnabled = allowCollection && settings.analyticsConsent;
        // On web, constructing the JS analytics SDK can send installation and
        // configuration requests. Defer it until explicit account consent.
        if (analyticsEnabled) _analytics ??= _analyticsFactory?.call();
        await _analytics?.setAnalyticsCollectionEnabled(analyticsEnabled);
        if (epoch != _accountEpoch) return;
        await _crashlytics?.setCrashlyticsCollectionEnabled(
          allowCollection && settings.crashReportingConsent,
        );
        if (epoch != _accountEpoch) return;
        if (persist &&
            !await _preferences.setString(key, jsonEncode(settings.toJson()))) {
          throw const StorageFailure(
            'Privacy preferences could not be saved on this device.',
          );
        }
        if (epoch == _accountEpoch) _current = settings;
      }),
    );
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> recordError(Object error, StackTrace stack) async {
    if (allowCollection && _current.crashReportingConsent) {
      // Never forward raw exception messages, which can contain private payloads.
      await _crashlytics?.recordError(
        StateError(error.runtimeType.toString()),
        stack,
        fatal: false,
      );
    }
  }
}
