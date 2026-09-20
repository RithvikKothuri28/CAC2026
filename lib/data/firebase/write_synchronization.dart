import 'dart:async';

import '../../core/errors/app_failure.dart';
import 'firebase_failure.dart';

class FarmSyncStatus {
  const FarmSyncStatus({
    this.hasPendingWrites = false,
    this.isFromCache = true,
    this.failure,
  });
  final bool hasPendingWrites;
  final bool isFromCache;
  final AppFailure? failure;
  String get message {
    if (failure != null) return failure!.message;
    if (hasPendingWrites)
      return 'Changes queued on this device · awaiting cloud confirmation';
    if (isFromCache)
      return 'Using cached farm data · cloud connection not confirmed';
    return 'All changes confirmed by the cloud';
  }
}

/// Bounds the UI wait without cancelling Firestore's queue. Late rejection is
/// published to sync state; the acknowledgement is never silently discarded.
class WriteSynchronization {
  WriteSynchronization({this.acknowledgementWait = const Duration(seconds: 3)});
  final Duration acknowledgementWait;
  final _changes = StreamController<FarmSyncStatus>.broadcast();
  int _inFlight = 0;
  bool _metadataPending = false;
  bool _fromCache = true;
  AppFailure? _failure;
  bool _closed = false;

  FarmSyncStatus get current => FarmSyncStatus(
    hasPendingWrites: _inFlight > 0 || _metadataPending,
    isFromCache: _fromCache,
    failure: _failure,
  );
  Stream<FarmSyncStatus> get status => Stream.multi((controller) {
    controller.add(current);
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
  void _emit() {
    if (!_closed) _changes.add(current);
  }

  void updateMetadata({
    required bool hasPendingWrites,
    required bool isFromCache,
  }) {
    _metadataPending = hasPendingWrites;
    _fromCache = isFromCache;
    _emit();
  }

  Future<void> track(Future<void> write) async {
    _inFlight++;
    _failure = null;
    _emit();
    final acknowledgement = write.then<void>(
      (_) {
        _inFlight--;
        _emit();
      },
      onError: (Object error, StackTrace stack) {
        _inFlight--;
        _failure = firebaseFailure(error);
        _emit();
        Error.throwWithStackTrace(_failure!, stack);
      },
    );
    await acknowledgement.timeout(acknowledgementWait, onTimeout: () {});
  }

  Future<void> close() async {
    _closed = true;
    await _changes.close();
  }
}
