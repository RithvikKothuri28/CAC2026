import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_failure.dart';
import 'firebase_failure.dart';

class UserSettings {
  const UserSettings({
    this.analyticsConsent = false,
    this.crashReportingConsent = false,
    this.cloudAssistantConsent = false,
  });
  final bool analyticsConsent;
  final bool crashReportingConsent;
  final bool cloudAssistantConsent;
  Map<String, dynamic> toJson() => {
    'analyticsConsent': analyticsConsent,
    'crashReportingConsent': crashReportingConsent,
    'cloudAssistantConsent': cloudAssistantConsent,
  };
  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
    analyticsConsent: json['analyticsConsent'] == true,
    crashReportingConsent: json['crashReportingConsent'] == true,
    cloudAssistantConsent: json['cloudAssistantConsent'] == true,
  );
  UserSettings copyWith({
    bool? analyticsConsent,
    bool? crashReportingConsent,
    bool? cloudAssistantConsent,
  }) => UserSettings(
    analyticsConsent: analyticsConsent ?? this.analyticsConsent,
    crashReportingConsent: crashReportingConsent ?? this.crashReportingConsent,
    cloudAssistantConsent: cloudAssistantConsent ?? this.cloudAssistantConsent,
  );
}

class FirestoreSettingsRepository {
  const FirestoreSettingsRepository(this._firestore, this._auth);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  DocumentReference<Map<String, dynamic>> get _document {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AuthenticationFailure('Sign in to save account settings.');
    }
    return _firestore.collection('users').doc(uid);
  }

  Future<UserSettings> read() => firebaseGuard(() async {
    final json = (await _document.get()).data();
    if (json == null) return const UserSettings();
    if (json['schemaVersion'] != 1 || json['settings'] is! Map) {
      throw const DataValidationFailure(
        'Your privacy settings use an unsupported format. Collection stays disabled.',
      );
    }
    return UserSettings.fromJson(
      Map<String, dynamic>.from(json['settings'] as Map),
    );
  });
  Future<void> save(UserSettings settings) => firebaseGuard(() async {
    await _document.set({
      'schemaVersion': 1,
      'settings': settings.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
}
