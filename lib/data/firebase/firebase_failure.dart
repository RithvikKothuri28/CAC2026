import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../../core/errors/app_failure.dart';

AppFailure firebaseFailure(Object error) {
  if (error is AppFailure) return error;
  if (error is TimeoutException) {
    return NetworkFailure(
      'The service took too long to respond. Check your connection and retry.',
      cause: error,
    );
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'unauthenticated' ||
      'user-token-expired' ||
      'invalid-user-token' => AuthenticationFailure(
        'Sign in again to continue.',
        code: error.code,
        cause: error,
      ),
      'wrong-password' ||
      'invalid-credential' ||
      'user-not-found' ||
      'invalid-email' => AuthenticationFailure(
        'The email or password could not be verified.',
        code: error.code,
        cause: error,
      ),
      'email-already-in-use' => AuthenticationFailure(
        'An account already uses this email. Sign in or reset your password.',
        code: error.code,
        cause: error,
      ),
      'weak-password' => AuthenticationFailure(
        'Choose a stronger password with at least eight characters.',
        code: error.code,
        cause: error,
      ),
      'requires-recent-login' || 'failed-precondition' => AuthenticationFailure(
        'Sign in again before completing this sensitive action.',
        code: error.code,
        cause: error,
      ),
      'permission-denied' => PermissionFailure(
        'You do not have permission to change or view this record.',
        code: error.code,
        cause: error,
      ),
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => NetworkFailure(
        'Cloud data is unavailable. Cached farm data remains usable; reconnect to synchronize.',
        code: error.code,
        cause: error,
      ),
      'too-many-requests' || 'resource-exhausted' => NetworkFailure(
        'The service is temporarily at its request limit. Try again later.',
        code: error.code,
        cause: error,
      ),
      'not-found' => RepositoryUnavailableFailure(
        'The requested record no longer exists.',
        code: error.code,
        cause: error,
      ),
      'invalid-argument' => DataValidationFailure(
        'The service could not accept this data. Check the input and retry.',
        code: error.code,
        cause: error,
      ),
      _ => StorageFailure(
        'The cloud operation could not be completed. Please retry.',
        code: error.code,
        cause: error,
      ),
    };
  }
  return StorageFailure(
    'The operation could not be completed. Your farm has not been replaced with sample data.',
    cause: error,
  );
}

Future<T> firebaseGuard<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on Object catch (error) {
    throw firebaseFailure(error);
  }
}
