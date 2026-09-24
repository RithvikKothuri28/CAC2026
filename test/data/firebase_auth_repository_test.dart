import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:farmtwin/data/data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _Functions extends Fake implements FirebaseFunctions {}

class _User extends Fake implements User {
  String? enteredDisplayName;
  Completer<void>? profileGate;
  Completer<void>? verificationGate;
  bool verificationRequested = false;

  @override
  Future<void> updateDisplayName(String? displayName) async {
    enteredDisplayName = displayName;
    if (profileGate != null) await profileGate!.future;
  }

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    verificationRequested = true;
    if (verificationGate != null) await verificationGate!.future;
  }
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
}

class _Auth extends Fake implements FirebaseAuth {
  final account = _User();
  int creations = 0;
  String? enteredEmail;

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creations++;
    enteredEmail = email;
    return _Credential(account);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'signup awaits Firebase profile update and verification dispatch',
    () async {
      final auth = _Auth();
      auth.account.profileGate = Completer<void>();
      auth.account.verificationGate = Completer<void>();
      final repository = FirebaseAuthRepository(auth, _Functions());
      var finished = false;
      final signup = repository
          .signUp(
            ' farmer@example.test ',
            'test-only-password',
            displayName: ' Farmer name ',
          )
          .then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(auth.creations, 1);
      expect(auth.enteredEmail, 'farmer@example.test');
      expect(auth.account.enteredDisplayName, 'Farmer name');
      expect(auth.account.verificationRequested, isFalse);
      expect(finished, isFalse);
      auth.account.profileGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(auth.account.verificationRequested, isTrue);
      expect(finished, isFalse);
      auth.account.verificationGate!.complete();
      await signup;
      expect(finished, isTrue);
    },
  );

  test('signup validates display name before creating the account', () async {
    final auth = _Auth();
    final repository = FirebaseAuthRepository(auth, _Functions());
    await expectLater(
      repository.signUp(
        'farmer@example.test',
        'test-only-password',
        displayName: ' ',
      ),
      throwsA(isA<DataValidationFailure>()),
    );
    expect(auth.creations, 0);
  });

  test(
    'verification failure explains that the account already exists',
    () async {
      final auth = _Auth();
      auth.account.verificationGate = Completer<void>();
      final repository = FirebaseAuthRepository(auth, _Functions());
      final failure = expectLater(
        repository.signUp('farmer@example.test', 'test-only-password'),
        throwsA(
          isA<AuthenticationFailure>()
              .having(
                (error) => error.message,
                'message',
                contains('account was created'),
              )
              .having(
                (error) => error.code,
                'Firebase code',
                'network-request-failed',
              ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      auth.account.verificationGate!.completeError(
        FirebaseAuthException(code: 'network-request-failed'),
      );
      await failure;
      expect(auth.creations, 1);
    },
  );
}
