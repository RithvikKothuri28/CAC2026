import 'dart:io';
import 'package:farmtwin/app/farmtwin_app.dart';
import 'package:farmtwin/core/widgets/model_editor.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'launch is empty, sample is explicit, and all workspace pages render',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = await SampleFarmRepository.open(
        loadAsset: (path) async => File(path).readAsStringSync(),
      );
      final state = WorkspaceController(sampleRepository: repo, cloud: null);
      addTearDown(state.dispose);
      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      expect(find.text('Load Sample Farm'), findsOneWidget);
      expect(state.farm, isNull);
      await tester.tap(find.text('Load Sample Farm'));
      await tester.pumpAndSettle();
      expect(find.text('Your farm, connected.'), findsOneWidget);
      expect(state.farm!.provenance.source.name, 'sample');
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
    },
  );

  testWidgets(
    'small mobile viewport renders dashboard and navigation without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = await SampleFarmRepository.open(
        loadAsset: (path) async => File(path).readAsStringSync(),
      );
      final state = WorkspaceController(sampleRepository: repo, cloud: null);
      addTearDown(state.dispose);
      await state.openSample();
      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Farm'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

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
}
