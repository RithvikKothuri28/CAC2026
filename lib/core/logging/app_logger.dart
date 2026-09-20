import 'dart:developer' as developer;

import '../errors/app_failure.dart';

/// Logs operation identifiers, never user records, names, questions or amounts.
abstract interface class AppLogger {
  void info(String operation);
  void warning(String operation, {String? code});
  void error(String operation, Object error, StackTrace stack);
}

class SafeAppLogger implements AppLogger {
  const SafeAppLogger({required this.development, this.reportError});
  final bool development;
  final Future<void> Function(Object, StackTrace)? reportError;

  @override
  void info(String operation) {
    if (development) developer.log(operation, name: 'FarmTwin');
  }

  @override
  void warning(String operation, {String? code}) {
    if (development) {
      developer.log(
        '$operation (${code ?? 'unavailable'})',
        name: 'FarmTwin',
        level: 900,
      );
    }
  }

  @override
  void error(String operation, Object error, StackTrace stack) {
    // Exception messages can contain PII or payloads; report only safe metadata.
    final sanitized = StateError(
      '$operation: ${error.runtimeType}'
      '${error is AppFailure ? ' (${error.code ?? 'unknown'})' : ''}',
    );
    if (development) {
      developer.log(sanitized.toString(), name: 'FarmTwin', level: 1000);
    }
    final reporter = reportError;
    if (reporter != null) {
      reporter(sanitized, stack).catchError((Object _) {});
    }
  }
}
