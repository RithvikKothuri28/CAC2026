import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:farmtwin/app/config/app_config.dart';
import 'package:farmtwin/app/farmtwin_app.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'new farmer enters inputs through forms and recovers saved work',
    (tester) async {
      final frameworkErrors = <String>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        frameworkErrors.add(details.toString());
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      var phase = 'startup';
      final config = AppConfig.fromEnvironment();
      // Guard before initializing an SDK or making any network request.
      expect(config.environment, AppEnvironment.development);
      expect(config.useEmulators, isTrue);
      expect(config.firebaseOptions?.projectId, 'demo-farmtwin');
      expect([
        '127.0.0.1',
        'localhost',
        '10.0.2.2',
      ], contains(config.emulatorHost));
      final cloud = (await FirebaseBootstrap.initialize(config))!;
      await cloud.auth.signOut();
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var state = WorkspaceController(sampleRepository: null, cloud: cloud);
      final email = 'ui-${DateTime.now().microsecondsSinceEpoch}@example.test';
      const password = 'Local-emulator-only-42!';
      addTearDown(() async {
        state.dispose();
        if (cloud.auth.currentUser?.email == email) {
          await cloud.auth.deleteAccount();
        }
      });

      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('UI timed out: ${state.error}');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 15),
        );
        expect(state.error, isNull, reason: phase);
        expect(
          tester.takeException(),
          isNull,
          reason: '$phase\n${frameworkErrors.join('\n')}',
        );
      }

      Future<void> tap(String label) async {
        phase = 'Tap $label';
        final finder = find.text(label);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 15),
        );
      }

      Future<void> input(String label, String value) async {
        phase = 'Enter $label';
        final finder = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(finder);
        await tester.enterText(finder, value);
        await tester.pump();
      }

      Future<void> navigate(String label) async {
        await tester.tap(find.widgetWithText(ListTile, label));
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await tap('Save');
        await until(
          () => !state.busy && find.byType(AlertDialog).evaluate().isEmpty,
        );
      }

      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      expect(state.farm, isNull);
      await tap('Sign in or create account');
      await tap('Create an account');
      await input('Email', email);
      await input('Password', password);
      await tap('Create account');
      await until(
        () => state.signedIn && find.byType(AlertDialog).evaluate().isEmpty,
      );
      await tap('Create your farm');
      await input('Farm name', 'New farmer UI fixture');
      await tap('Create farm');
      await until(() => state.farm != null && !state.busy);
      expect(state.farm!.fields, isEmpty);
      expect(state.sampleMode, isFalse);

      await navigate('My farm');
      await tap('Crops');
      for (final crop in [
        ('Alpha fixture', '20', '10', '20', '2'),
        ('Beta fixture', '30', '8', '25', '3'),
      ]) {
        await tap('Add crop');
        await input('Name', crop.$1);
        await input('Expected yield / acre', crop.$2);
        await input('Expected price / yield unit', crop.$3);
        await input('Yield unit (e.g. bushels)', 'units');
        await input('Seed Cost Per Acre', crop.$4);
        await input('Water (acre-feet / acre)', crop.$5);
        await input('Rotation Family', crop.$1);
        await save();
      }
      expect(state.farm!.crops, hasLength(2));
      await tap('Fields');
      await tap('Add field');
      await input('Name', 'Entered field');
      await input('Area (acres)', '10');
      await save();
      expect(state.farm!.fields, hasLength(1));

      await tap('Finances');
      await tap('Add expense');
      await input('Name', 'Entered rent');
      await input('Annual Amount', '100');
      await save();
      await tap('Add debt');
      await input('Name', 'Entered loan');
      await input('Balance', '1000');
      await input('Annual interest rate (fraction)', '0.05');
      await input('Annual Payment', '100');
      await save();
      expect(state.financial!.operatingIncome, 1700);
      expect(state.financial!.cashAfterDebt, 1600);

      await tap('Constraints');
      await tap('Add rule');
      await input('Name', 'Entered water cap');
      await input('Limit (fractions for share constraints)', '35');
      await save();
      await navigate('Optimize');
      await tap('Run optimization');
      await until(() => state.optimization != null && !state.busy);
      // Independent arithmetic: 10 * (30 * 8 - 25) - 100 fixed cost.
      expect(state.selected!.financial.operatingIncome, 2050);
      expect(state.optimization!.diagnostics.candidatesGenerated, 2);
      await tap('Save run');
      await until(() => !state.busy);
      await navigate('Risk & outlook');
      await tap('Run simulation');
      await until(() => state.risk != null && !state.busy);
      expect(state.risk!.alternative!.mean, 1950);
      expect(state.risk!.alternative!.standardDeviation, 0);
      await tap('Save simulation');
      await until(() => !state.busy);

      await navigate('Scenario lab');
      await tap('Create scenario');
      await input('Name', 'Entered price shock');
      await input('Price Multiplier', '0.7');
      await save();
      await tap('Re-optimize scenario');
      await until(() => state.scenarioResult != null && !state.busy);
      expect(
        state.scenarioResult!.recommended!.financial.operatingIncome,
        1330,
      );
      await tap('Simulate scenario');
      await until(() => state.scenarioRisk != null && !state.busy);
      expect(state.scenarioRisk!.alternative!.mean, 1230);
      expect(state.scenarioRisk!.current.mean, 1000);
      await tap('Save scenario simulation');
      await until(() => !state.busy);

      await FirebaseFirestore.instance.waitForPendingWrites();
      final persistedInput = state.farm!.toJson();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      // Recreate the entire application/controller, retaining the SDK login.
      state = WorkspaceController(sampleRepository: null, cloud: cloud);
      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await until(() => state.farm != null);
      expect(state.farm!.toJson(), persistedInput);
      expect(state.optimization, isNull);
      await navigate('Settings');
      await until(
        () =>
            find
                .text('Calculated summary with input snapshot')
                .evaluate()
                .length ==
            3,
      );
      await tap('Sign out');
      await until(() => !state.signedIn && state.farm == null && !state.busy);
      await tap('Sign in or create account');
      await input('Email', email);
      await input('Password', password);
      await tap('Sign in');
      await until(
        () => state.farm != null && find.byType(AlertDialog).evaluate().isEmpty,
      );
      expect(state.farm!.toJson(), persistedInput);
      await navigate('Settings');
      await until(
        () =>
            find
                .text('Calculated summary with input snapshot')
                .evaluate()
                .length ==
            3,
      );

      // Canceling identity confirmation must cancel deletion altogether.
      await tap('Delete account and data');
      await tap('Confirm');
      await tap('Cancel');
      expect(find.text('Complete account deletion?'), findsNothing);
      expect(state.signedIn, isTrue);
      await tap('Delete account and data');
      await tap('Confirm');
      await input('Password', password);
      await tap('Confirm');
      await until(
        () => find.text('Complete account deletion?').evaluate().isNotEmpty,
      );
      await tap('Confirm');
      await until(() => !state.signedIn && state.farm == null && !state.busy);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
