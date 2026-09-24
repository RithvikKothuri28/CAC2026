import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:farmtwin/app/config/app_config.dart';
import 'package:farmtwin/app/farmtwin_app.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';

/// Explicitly opt-in cloud verification. Credentials belong in an ignored
/// dart-define file. This target leaves its verification farm for console review.
/// Normal CI uses the isolated demo project and never runs this target.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Firebase account and farm survive edits and sign-ins', (
    tester,
  ) async {
    const allowed = bool.fromEnvironment('ALLOW_LIVE_FIREBASE_TEST');
    const email = String.fromEnvironment('LIVE_TEST_EMAIL');
    const password = String.fromEnvironment('LIVE_TEST_PASSWORD');
    const farmName = String.fromEnvironment(
      'LIVE_TEST_FARM_NAME',
      defaultValue: 'Firebase connectivity verification',
    );
    final config = AppConfig.fromEnvironment();
    // Run every guard before initializing Firebase or issuing a network request.
    expect(
      allowed,
      isTrue,
      reason: 'Live writes require an explicit test opt-in.',
    );
    expect(config.useEmulators, isFalse);
    expect(config.firebaseOptions?.projectId, 'farmtwin-f64bd');
    expect(email, isNotEmpty);
    expect(password.length, greaterThanOrEqualTo(12));
    final cloud = await FirebaseBootstrap.initialize(config);
    expect(Firebase.app().options.projectId, 'farmtwin-f64bd');
    await cloud.auth.signOut();
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var state = WorkspaceController(cloud: cloud);
    addTearDown(() => state.dispose());

    Future<void> until(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'Live UI operation did not complete: ${state.error ?? "inspect the visible dialog error"}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(state.error, isNull);
      expect(tester.takeException(), isNull);
    }

    Future<void> tap(String text) async {
      final finder = find.text(text);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      // Network progress indicators must not make pumpAndSettle time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> input(String label, String text) async {
      final finder = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(finder);
      await tester.enterText(finder, text);
      await tester.pump();
    }

    Future<void> settings() async {
      await tester.tap(find.widgetWithText(ListTile, 'Settings'));
      await tester.pumpAndSettle();
    }

    Future<void> signIn() async {
      await tap('Sign in or create account');
      await input('Email', email);
      await input('Password', password);
      await tap('Sign in');
      await until(
        () => state.signedIn && find.byType(AlertDialog).evaluate().isEmpty,
      );
    }

    await tester.pumpWidget(FarmTwinApp(workspace: state));
    await tester.pumpAndSettle();
    await tap('Sign in or create account');
    await tap('Create an account');
    await input('Display name', 'Connectivity verification');
    await input('Email', email);
    await input('Password', password);
    await input('Confirm password', password);
    await tap('Create account');
    await until(
      () => state.signedIn && find.byType(AlertDialog).evaluate().isEmpty,
    );
    final uid = FirebaseAuth.instance.currentUser!.uid;
    expect(cloud.auth.currentUser!.uid, uid);
    await tap('Sign out');
    await until(() => !state.signedIn);
    await signIn();
    expect(FirebaseAuth.instance.currentUser!.uid, uid);

    await tap('Add New Farm');
    await input('Farm name', farmName);
    await input('Country', 'Canada');
    await input('State or region', 'Alberta');
    await input('Currency code', 'CAD');
    await input('Total farm acres', '127.5');
    await tap('Save');
    await until(
      () => state.farm != null && find.byType(AlertDialog).evaluate().isEmpty,
    );
    final farmId = state.farm!.id;
    final reference = FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId);
    var server = await reference.get(const GetOptions(source: Source.server));
    expect(server.exists, isTrue);
    expect(server.metadata.hasPendingWrites, isFalse);
    expect(server.data()!['ownerId'], uid);
    expect(server.data()!['createdAt'], isA<Timestamp>());
    final entered = server.data()!['data'] as Map;
    expect(entered['name'], farmName);
    expect(entered['country'], 'Canada');
    expect(entered['region'], 'Alberta');
    expect(entered['declaredAcres'], 127.5);
    expect((entered['settings'] as Map)['currencyCode'], 'CAD');
    final member = await reference
        .collection('members')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    expect(member.exists, isTrue);
    expect(member.data()!['userId'], uid);
    expect(member.data()!['role'], 'owner');

    // Recreate the app/controller and reread the server. A full browser refresh
    // is also verified externally, because replacing widgets is not a reload.
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    state = WorkspaceController(cloud: cloud);
    await tester.pumpWidget(FarmTwinApp(workspace: state));
    await until(() => state.farm?.id == farmId);
    expect(state.farm!.name, farmName);
    await settings();
    await tap('Rename farm');
    await input('Name', '$farmName edited');
    await tap('Save');
    await until(
      () =>
          state.farm?.name == '$farmName edited' &&
          find.byType(AlertDialog).evaluate().isEmpty,
    );
    server = await reference.get(const GetOptions(source: Source.server));
    expect(server.data()!['name'], '$farmName edited');
    expect(server.data()!['updatedAt'], isA<Timestamp>());

    await tap('Sign out');
    await until(() => !state.signedIn && state.farm == null);
    await signIn();
    await until(() => state.farm?.id == farmId);
    expect(state.farm!.name, '$farmName edited');
    expect(FirebaseAuth.instance.currentUser!.uid, uid);
    server = await reference.get(const GetOptions(source: Source.server));
    expect(server.exists, isTrue);
    binding.reportData = {
      'projectId': Firebase.app().options.projectId,
      'uid': uid,
      'farmId': farmId,
      'farmPath': reference.path,
      'ownerMemberVerified': true,
      'createEditSignInVerified': true,
      'actualBrowserRefreshVerified': false,
    };
    debugPrint(
      'FARMTWIN_LIVE_VERIFIED project=farmtwin-f64bd uid=$uid path=${reference.path}',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
