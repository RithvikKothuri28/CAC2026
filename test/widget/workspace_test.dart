import 'dart:async';
import 'package:farmtwin/app/farmtwin_app.dart';
import 'package:farmtwin/core/widgets/model_editor.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/firebase_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-in Firestore workspace renders all workspace pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cloud = TestCloud(farms: TestFarms([fixtureFarm()]));
    addTearDown(cloud.close);
    final state = WorkspaceController(cloud: cloud);
    addTearDown(state.dispose);
    await tester.pumpWidget(FarmTwinApp(workspace: state));
    await tester.pumpAndSettle();
    expect(find.text('Your farm, connected.'), findsOneWidget);
    expect(state.farm, isNotNull);
    expect(find.text('Load Sample Farm'), findsNothing);
    for (final title in [
      'My farm',
      'Optimize',
      'Risk & outlook',
      'Scenario lab',
      'Assistant',
      'Harvest passports',
      'Settings',
      'Overview',
    ]) {
      await tester.tap(find.widgetWithText(ListTile, title));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: title);
    }
  });

  testWidgets(
    'small mobile viewport renders dashboard and navigation without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cloud = TestCloud(farms: TestFarms([fixtureFarm()]));
      addTearDown(cloud.close);
      final state = WorkspaceController(cloud: cloud);
      addTearDown(state.dispose);
      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Farm'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('farm creation awaits acceptance and preserves inputs on retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cloud = TestCloud();
    addTearDown(cloud.close);
    final state = WorkspaceController(cloud: cloud);
    addTearDown(state.dispose);
    await tester.pumpWidget(FarmTwinApp(workspace: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Farm'));
    await tester.pumpAndSettle();
    for (final entry in {
      'Farm name': 'Entered farm',
      'Country': 'Canada',
      'State or region': 'Alberta',
      'Currency code': 'cad',
      'Total farm acres': '127.5',
    }.entries) {
      await tester.enterText(
        find.widgetWithText(TextFormField, entry.key),
        entry.value,
      );
    }
    cloud.farms.acknowledgement = Completer<void>();
    cloud.farms.saveFailure = const PermissionFailure(
      'permission-denied: account cannot create this farm',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(state.farm, isNull);
    expect(cloud.farms.writes, hasLength(1));
    final first = cloud.farms.writes.single;
    expect(first.name, 'Entered farm');
    expect(first.country, 'Canada');
    expect(first.region, 'Alberta');
    expect(first.settings.currencyCode, 'CAD');
    expect(first.declaredAcres, 127.5);
    cloud.farms.acknowledgement!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('permission-denied'), findsOneWidget);
    expect(state.farm, isNull);
    cloud.farms.saveFailure = null;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(state.farm!.id, first.id);
    expect(cloud.farms.writes.last.id, first.id);
  });

  testWidgets('signed-out startup offers authentication and no farm creation', (
    tester,
  ) async {
    final cloud = TestCloud(auth: TestAuth(signedIn: false));
    addTearDown(cloud.close);
    final state = WorkspaceController(cloud: cloud);
    addTearDown(state.dispose);
    await tester.pumpWidget(FarmTwinApp(workspace: state));
    await tester.pumpAndSettle();
    expect(find.text('Sign in or create account'), findsOneWidget);
    expect(find.text('Add New Farm'), findsNothing);
    expect(find.text('Load Sample Farm'), findsNothing);
    await expectLater(
      state.createFarm(
        name: 'Denied',
        country: 'US',
        region: 'CO',
        currencyCode: 'USD',
        declaredAcres: 1,
      ),
      throwsA(isA<AuthenticationFailure>()),
    );
    expect(cloud.farms.writes, isEmpty);
  });

  testWidgets(
    'numeric form keeps fractional edits even when JSON starts at integer zero',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Edit'),
                onPressed: () async {
                  saved = await editModel(
                    context,
                    title: 'Assumptions',
                    initial: {
                      'priceGrowthRate': 0,
                      'weights': {'profit': 1, 'resilience': 0},
                    },
                    validate: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '0.025');
      await tester.enterText(find.byType(TextFormField).at(1), '0.75');
      await tester.enterText(find.byType(TextFormField).at(2), '0.25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!['priceGrowthRate'], 0.025);
      expect((saved!['weights'] as Map)['profit'], 0.75);
    },
  );

  testWidgets(
    'integer form accepts whole decimal and exponent notation and rejects fractions',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Edit'),
                onPressed: () async {
                  saved = await editModel(
                    context,
                    title: 'Simulation settings',
                    initial: {'seed': 1, 'iterations': 500},
                    validate: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, '1.0');
      await tester.enterText(fields.at(1), '1.5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number'), findsOneWidget);
      expect(saved, isNull);
      expect(tester.takeException(), isNull);

      await tester.enterText(fields.at(1), '1e3');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, {'seed': 1, 'iterations': 1000});
      expect(saved!['seed'], isA<int>());
      expect(saved!['iterations'], isA<int>());
      expect(tester.takeException(), isNull);
    },
  );
}
