import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_failure.dart';
import 'firebase_failure.dart';

class FirebaseAuthRepository {
  const FirebaseAuthRepository(this._auth, this._functions);
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges().handleError(
    (Object error) => throw firebaseFailure(error),
  );

  void _validateCredentials(String email, String password) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw const DataValidationFailure('Enter a valid email address.');
    }
    if (password.isEmpty) {
      throw const DataValidationFailure('Enter your password.');
    }
  }

  Future<void> signIn(String email, String password) => firebaseGuard(() async {
    _validateCredentials(email, password);
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  });

  Future<void> signUp(String email, String password) => firebaseGuard(() async {
    _validateCredentials(email, password);
    if (password.length < 8) {
      throw const DataValidationFailure(
        'Use at least eight characters for your password.',
      );
    }
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  });

  Future<void> resetPassword(String email) => firebaseGuard(() async {
    _validateCredentials(email, 'reset');
    await _auth.sendPasswordResetEmail(email: email.trim());
  });

  Future<void> signOut() => firebaseGuard(_auth.signOut);

  Future<void> reauthenticate(String email, String password) =>
      firebaseGuard(() async {
        _validateCredentials(email, password);
        final user = _auth.currentUser;
        if (user == null) {
          throw const AuthenticationFailure('Sign in to continue.');
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email.trim(), password: password),
        );
      });

  Future<void> deleteAccount() => firebaseGuard(() async {
    if (_auth.currentUser == null) {
      throw const AuthenticationFailure('Sign in to delete your account.');
    }
    await _functions.httpsCallable('deleteAccount').call<void>({});
    await _auth.signOut();
  });
}
