import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../app/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import 'firebase_development_logger.dart';
import 'firebase_failure.dart';

/// Manually invoked, debug-build-only check. Production builds cannot run it.
/// Rules additionally require the server-issued farmtwinDeveloper custom claim.
class FirebaseConnectivityDiagnostic {
  const FirebaseConnectivityDiagnostic(this.config);
  final AppConfig config;
  bool get enabled =>
      kDebugMode &&
      config.isDevelopment &&
      config.enableConnectivityDiagnostic &&
      !config.useEmulators;

  Future<String> run() async {
    if (!enabled) {
      throw const ConfigurationFailure('Firebase diagnostics are disabled.');
    }
    if (Firebase.apps.isEmpty) {
      throw const ConfigurationFailure('Firebase has not initialized.');
    }
    final app = Firebase.app();
    if (app.options.projectId != 'farmtwin-f64bd') {
      throw const ConfigurationFailure('Unexpected Firebase project.');
    }
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) {
      throw const AuthenticationFailure(
        'Sign in before running the diagnostic.',
      );
    }
    final token = await user.getIdTokenResult(true);
    if (token.claims?['farmtwinDeveloper'] != true) {
      throw const PermissionFailure(
        'This account is not authorized for development diagnostics.',
      );
    }
    final firestore = FirebaseFirestore.instance;
    final ref = firestore
        .collection('developmentDiagnostics')
        .doc(user.uid)
        .collection('checks')
        .doc();
    const logger = FirebaseDevelopmentLogger(enabled: true);
    void log(String operation, [Object? error]) => logger.event(
      operation,
      uid: user.uid,
      projectId: app.options.projectId,
      path: ref.path,
      error: error,
    );
    void requireSameUser() {
      if (auth.currentUser?.uid != user.uid) {
        throw const AuthenticationFailure('The signed-in account changed.');
      }
    }

    try {
      requireSameUser();
      log('diagnostic_write_start');
      await ref
          .set({
            'schemaVersion': 1,
            'ownerId': user.uid,
            'projectId': app.options.projectId,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
      log('diagnostic_write_success');
      requireSameUser();
      final snapshot = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!snapshot.exists ||
          snapshot.data()?['ownerId'] != user.uid ||
          snapshot.data()?['createdAt'] is! Timestamp) {
        throw const StorageFailure(
          'The server did not return the diagnostic document.',
        );
      }
      log('diagnostic_read_success');
      requireSameUser();
      await ref.delete().timeout(const Duration(seconds: 20));
      final deleted = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (deleted.exists) {
        throw const StorageFailure('Diagnostic cleanup was not confirmed.');
      }
      log('diagnostic_delete_success');
      return 'Firebase initialized; project farmtwin-f64bd; user authenticated; '
          'Firestore server write, read and delete confirmed.';
    } catch (error) {
      log('diagnostic_failure', error);
      // Never report success after a timeout; a pending SDK write may later finish.
      if (auth.currentUser?.uid == user.uid) {
        try {
          await ref.delete().timeout(const Duration(seconds: 5));
        } catch (cleanupError) {
          log('diagnostic_cleanup_failure', cleanupError);
        }
      }
      throw firebaseFailure(error);
    }
  }
}
