/// Failures safe to present to a farmer. Technical exceptions stay out of the UI.
abstract class AppFailure implements Exception {
  const AppFailure(this.message, {this.code, this.cause});
  final String message;
  final String? code;
  final Object? cause;
  @override
  String toString() => message;
}

class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure(super.message, {super.code, super.cause});
}

class AuthenticationFailure extends AppFailure {
  const AuthenticationFailure(super.message, {super.code, super.cause});
}

class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {super.code, super.cause});
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.code, super.cause});
}

class RepositoryUnavailableFailure extends AppFailure {
  const RepositoryUnavailableFailure(super.message, {super.code, super.cause});
}

class DataValidationFailure extends AppFailure {
  const DataValidationFailure(super.message, {super.code, super.cause});
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.code, super.cause});
}

class AiProviderFailure extends AppFailure {
  const AiProviderFailure(super.message, {super.code, super.cause});
}
