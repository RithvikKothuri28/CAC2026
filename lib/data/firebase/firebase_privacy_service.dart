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
    FirebaseCrashlytics? crashlytics,
    this.allowCollection = true,
  }) : _preferences = preferences,
       _analytics = analytics,
       _crashlytics = crashlytics;
  final SharedPreferences _preferences;
  final FirebaseAnalytics? _analytics;
  final FirebaseCrashlytics? _crashlytics;
  final bool allowCollection;
  static const storageKey = 'farmtwin.privacy.v1';
  String _activeKey = storageKey;
  int _accountEpoch = 0;
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
    _current = const UserSettings();
    await apply(const UserSettings());
    if (uid == null || epoch != _accountEpoch) return;
    try {
      final settings = await readRemote().timeout(const Duration(seconds: 5));
      if (epoch == _accountEpoch) await apply(settings);
    } on Object {
      if (cached != null && epoch == _accountEpoch) {
        final saved = UserSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(cached) as Map),
        );
        await apply(saved);
      }
      rethrow;
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
    final epoch = _accountEpoch;
    final key = _activeKey;
    final result = _pending.then(
      (_) => firebaseGuard(() async {
        if (epoch != _accountEpoch) return;
        await _analytics?.setAnalyticsCollectionEnabled(
          allowCollection && settings.analyticsConsent,
        );
        await _crashlytics?.setCrashlyticsCollectionEnabled(
          allowCollection && settings.crashReportingConsent,
        );
        if (!await _preferences.setString(key, jsonEncode(settings.toJson()))) {
          throw const StorageFailure(
            'Privacy preferences could not be saved on this device.',
          );
        }
        _current = settings;
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
