import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';

/// Explicit debug-only connectivity logging. Never accepts a document payload,
/// credential, email, farm name, or financial value.
class FirebaseDevelopmentLogger {
  const FirebaseDevelopmentLogger({this.enabled = false});

  final bool enabled;

  void event(
    String operation, {
    String? uid,
    String? projectId,
    String? path,
    Object? error,
  }) {
    if (!enabled || !kDebugMode) return;
    final cause = error is AppFailure ? error.cause ?? error : error;
    final code = cause is FirebaseException
        ? cause.code
        : error is AppFailure
        ? error.code
        : null;
    // These messages come from the SDK/service, never from form inputs or an
    // arbitrary exception's toString (which may include a submitted payload).
    final message = cause is FirebaseException
        ? cause.message
        : error is AppFailure
        ? error.message
        : error?.runtimeType.toString();
    debugPrint(
      '[FarmTwin Firebase] $operation '
      'uid=${uid ?? "unauthenticated"} '
      'project=${projectId ?? "unavailable"} '
      'path=${path ?? "none"}'
      '${error == null ? "" : " code=${code ?? 'unknown'} message=$message"}',
    );
  }
}
