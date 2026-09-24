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

/// Explicit opt-in only. Uses an existing dedicated verification account and
/// creates a new, clearly named verification farm. It never edits existing farms.
/// Keep credentials in an ignored dart-define file, never source control.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Firebase preserves explicit crop compatibility through the UI',
    (tester) async {
      const allowed = bool.fromEnvironment('ALLOW_LIVE_FIREBASE_TEST');
      const cropFlowAllowed = bool.fromEnvironment('ALLOW_LIVE_CROP_FLOW_TEST');
      const email = String.fromEnvironment('LIVE_TEST_EMAIL');
      const password = String.fromEnvironment('LIVE_TEST_PASSWORD');
      final config = AppConfig.fromEnvironment();
      // All destination and authorization guards run before SDK initialization.
      expect(allowed, isTrue);
      expect(cropFlowAllowed, isTrue);
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
      var phase = 'sign in';

      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              '$phase did not complete: ${state.error ?? "inspect the dialog"}',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(state.error, isNull, reason: phase);
        expect(tester.takeException(), isNull, reason: phase);
      }

      Future<void> tapFinder(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> tap(String label) => tapFinder(find.text(label));

      Future<void> input(String label, String value) async {
        final finder = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(finder);
        await tester.enterText(finder, value);
        await tester.pump();
      }

      Future<void> navigate(String label) async {
        await tapFinder(find.widgetWithText(ListTile, label));
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await tap('Save');
        await until(
          () => !state.busy && find.byType(AlertDialog).evaluate().isEmpty,
        );
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

      DropdownButton<String> currentCropSelector() =>
          tester.widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(const ValueKey('field-current-crop')),
              matching: find.byType(DropdownButton<String>),
            ),
          );

      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      await signIn();
      final uid = FirebaseAuth.instance.currentUser!.uid;

      phase = 'create verification farm';
      final farmName =
          'Crop compatibility verification ${DateTime.now().toUtc().toIso8601String()}';
      final addFarm = find.byTooltip('Add New Farm');
      await tapFinder(
        addFarm.evaluate().isNotEmpty ? addFarm : find.text('Add New Farm'),
      );
      await input('Farm name', farmName);
      await input('Country', 'United States');
      await input('State or region', 'Colorado');
      await input('Currency code', 'USD');
      await input('Total farm acres', '10');
      await save();
      await until(() => state.farm?.name == farmName);
      final farmId = state.farm!.id;
      final reference = FirebaseFirestore.instance
          .collection('farms')
          .doc(farmId);
      final initial = await reference.get(
        const GetOptions(source: Source.server),
      );
      expect(initial.data()!['ownerId'], uid);
      expect(state.farm!.fields, isEmpty);
      expect(state.farm!.crops, isEmpty);
      expect(state.ready, isFalse);
      expect(state.financial, isNull);

      phase = 'add irrigation-dependent Corn profile';
      await navigate('My farm');
      await tap('Crops');
      await tap('Add crop');
      await input('Name', 'Corn');
      await input('Expected yield / acre', '20');
      await input('Expected price / yield unit', '10');
      await input('Yield unit (e.g. bushels)', 'units');
      await input('Seed Cost Per Acre', '20');
      await input('Water (acre-feet / acre)', '2');
      await input('Rotation Family', 'Corn');
      await tapFinder(
        find.widgetWithText(SwitchListTile, 'Requires Irrigation'),
      );
      await save();
      final cornId = state.farm!.crops.single.id;
      expect(cornId, isNot('Corn'));
      expect(state.farm!.crops.single.requiresIrrigation, isTrue);

      phase = 'new rainfed field has no selectable current crop';
      await tap('Fields');
      await tap('Add field');
      await input('Name', 'Field 1');
      await input('Area (acres)', '10');
      expect(
        currentCropSelector().items!.where((item) => item.value != ''),
        isEmpty,
      );
      expect(
        currentCropSelector().items!
            .map((item) => item.value)
            .where((id) => id != null && id.isNotEmpty),
        isEmpty,
      );
      final compatibility = find.byKey(ValueKey('field-compatible-$cornId'));
      expect(tester.widget<FilterChip>(compatibility).selected, isFalse);
      expect(tester.widget<FilterChip>(compatibility).onSelected, isNotNull);
      expect(tester.takeException(), isNull);

      phase = 'explicitly enable irrigation and compatible current Corn';
      await tapFinder(find.widgetWithText(SwitchListTile, 'Irrigated'));
      await tapFinder(compatibility);
      await tapFinder(find.byKey(const ValueKey('field-current-crop')));
      await tester.pumpAndSettle();
      await tapFinder(find.text('Corn').last);
      await save();
      final fieldId = state.farm!.fields.single.id;

      Future<void> verifyServer({required bool assigned}) async {
        final server = await reference.get(
          const GetOptions(source: Source.server),
        );
        expect(server.metadata.hasPendingWrites, isFalse);
        final data = server.data()!['data'] as Map<String, dynamic>;
        final field = (data['fields'] as List).single as Map<String, dynamic>;
        final crop = (data['crops'] as List).single as Map<String, dynamic>;
        expect(field['id'], fieldId);
        expect(field['irrigated'], isTrue);
        expect(field['currentCropId'], assigned ? cornId : '');
        expect(field['compatibleCropIds'], assigned ? [cornId] : isEmpty);
        expect(crop['id'], cornId);
        expect(crop['name'], 'Corn');
        expect(crop['requiresIrrigation'], isTrue);
      }

      Future<void> optimize() async {
        await navigate('Optimize');
        await tap('Run optimization');
        await until(() => state.optimization != null && !state.busy);
        expect(state.optimization!.diagnostics.candidatesGenerated, 1);
        expect(state.selected!.plan.assignments, {fieldId: cornId});
        expect(state.selected!.financial.operatingIncome, 1800);
      }

      await verifyServer(assigned: true);
      phase = 'optimize only the compatible Corn ID';
      await optimize();

      phase = 'edit removes compatibility and clears the current crop';
      await navigate('My farm');
      await tapFinder(find.byTooltip('Edit Field 1'));
      await tapFinder(compatibility);
      expect(
        find.textContaining('The current crop is not compatible'),
        findsOneWidget,
      );
      await tapFinder(find.byKey(const ValueKey('field-current-crop')));
      await tester.pumpAndSettle();
      await tapFinder(find.text('No current crop').last);
      await save();
      expect(state.farm!.fields.single.currentCropId, isEmpty);
      expect(state.farm!.fields.single.compatibleCropIds, isEmpty);
      expect(state.ready, isFalse);
      expect(state.financial, isNull);
      await verifyServer(assigned: false);

      // Recreating the controller resubscribes to the real Firebase repository;
      // this assertion does not claim to be a full browser process restart.
      phase = 'reload incomplete field without a framework exception';
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      state = WorkspaceController(cloud: cloud);
      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await until(() => state.farms.any((farm) => farm.id == farmId));
      state.selectFarm(state.farms.singleWhere((farm) => farm.id == farmId));
      await tester.pumpAndSettle();
      expect(state.farm!.fields.single.currentCropId, isEmpty);
      expect(state.ready, isFalse);
      expect(tester.takeException(), isNull);
      await verifyServer(assigned: false);

      phase = 'restore explicit compatibility and optimize after reload';
      await navigate('My farm');
      await tapFinder(find.byTooltip('Edit Field 1'));
      await tapFinder(compatibility);
      await tapFinder(find.byKey(const ValueKey('field-current-crop')));
      await tester.pumpAndSettle();
      await tapFinder(find.text('Corn').last);
      await save();
      await verifyServer(assigned: true);
      await optimize();

      phase = 'sign-in restores the same compatible crop IDs';
      await navigate('Settings');
      await tap('Sign out');
      await until(() => !state.signedIn && state.farm == null);
      await signIn();
      await until(() => state.farms.any((farm) => farm.id == farmId));
      state.selectFarm(state.farms.singleWhere((farm) => farm.id == farmId));
      await tester.pumpAndSettle();
      expect(state.farm!.fields.single.currentCropId, cornId);
      expect(state.farm!.fields.single.compatibleCropIds, [cornId]);
      await verifyServer(assigned: true);
      expect(tester.takeException(), isNull);

      binding.reportData = {
        'projectId': 'farmtwin-f64bd',
        'uid': uid,
        'farmPath': reference.path,
        'farmId': farmId,
        'cropId': cornId,
        'fieldId': fieldId,
        'irrigationMismatchPrevented': true,
        'explicitCompatibilityPersisted': true,
        'emptyCompatibilityReloadVerified': true,
        'optimizerOnlyCompatibleAssignments': true,
        'signInPreservesCropIds': true,
      };
      debugPrint(
        'FARMTWIN_CROP_FLOW_VERIFIED project=farmtwin-f64bd uid=$uid path=${reference.path}',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
