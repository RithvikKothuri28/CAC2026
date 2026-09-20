import 'package:farmtwin/app/farmtwin_app.dart';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'explicit sample, real engines, edited constraint, explanation and durable restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(SampleFarmRepository.storageKey);
      var state = WorkspaceController(
        sampleRepository: await SampleFarmRepository.open(),
        cloud: null,
      );
      addTearDown(() => state.dispose());

      Future<void> settledUntil(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out; workspace error: ${state.error}');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(state.error, isNull);
        expect(tester.takeException(), isNull);
      }

      Future<void> navigate(String title) async {
        await tester.tap(find.widgetWithText(ListTile, title));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      expect(state.farm, isNull);
      await tester.tap(find.text('Load Sample Farm'));
      await settledUntil(() => state.farm != null && !state.busy);
      expect(state.farm!.provenance.source, DataSourceType.sample);

      await navigate('Optimize');
      await tester.tap(find.text('Run optimization'));
      await settledUntil(() => state.optimization != null && !state.busy);
      final originalRun = state.optimization!;
      expect(originalRun.diagnostics.candidatesGenerated, greaterThan(0));
      expect(originalRun.recommended, isNotNull);
      expect(originalRun.recommended!.constraints.feasible, isTrue);
      final originalWater = originalRun.recommended!.financial.waterUsage;
      final waterRule = state.farm!.constraints.firstWhere(
        (c) => c.kind == ConstraintKind.maxWater,
      );
      final changedLimit = waterRule.limit * .6;

      await tester.tap(find.text('Edit constraints'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit ${waterRule.name}'));
      await tester.pumpAndSettle();
      final limitField = find.widgetWithText(
        TextFormField,
        'Limit (fractions for share constraints)',
      );
      await tester.ensureVisible(limitField);
      await tester.enterText(limitField, changedLimit.toString());
      await tester.tap(find.text('Save'));
      await settledUntil(
        () =>
            !state.busy &&
            state.farm!.constraints
                    .firstWhere((c) => c.id == waterRule.id)
                    .limit ==
                changedLimit,
      );
      expect(
        state.optimization,
        isNull,
        reason: 'Editing inputs must invalidate derived calculations.',
      );

      await navigate('Optimize');
      await tester.tap(find.text('Run optimization'));
      await settledUntil(() => state.optimization != null && !state.busy);
      final newRun = state.optimization!;
      expect(newRun.recommended!.financial.waterUsage, lessThan(originalWater));
      expect(
        newRun.recommended!.financial.waterUsage,
        lessThanOrEqualTo(changedLimit),
      );
      expect(
        newRun.recommended!.plan.toJson(),
        isNot(originalRun.recommended!.plan.toJson()),
      );
      await tester.tap(find.text('Save run'));
      await settledUntil(() => !state.busy);
      final saved = await state.repository!
          .watchEntities(state.farm!.id, EntityKind.optimizationRuns)
          .first;
      expect(saved, hasLength(1));
      expect(
        (saved.single.data['result'] as Map)['diagnostics'],
        newRun.diagnostics.toJson(),
      );

      await navigate('Risk & outlook');
      await tester.tap(find.text('Run simulation'));
      await settledUntil(() => state.risk != null && !state.busy);
      final risk = state.risk!;
      expect(
        risk.current.samples.length,
        state.farm!.settings.simulation.iterations,
      );
      expect(risk.alternative!.samples.length, risk.current.samples.length);
      expect(risk.alternative!.standardDeviation, greaterThan(0));
      expect(risk.alternative!.samples, isNot(risk.current.samples));
      await tester.tap(find.text('Save simulation'));
      await settledUntil(() => !state.busy);

      await navigate('Assistant');
      await tester.tap(
        find.widgetWithText(ActionChip, 'Explain my risk results'),
      );
      await tester.pumpAndSettle();
      final reply = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.data?.contains(
                  'Across ${risk.alternative!.iterations} simulated years',
                ) ??
                false),
      );
      expect(reply, findsOneWidget);
      expect(
        tester.widget<SelectableText>(reply).data,
        contains(risk.alternative!.mean.toStringAsFixed(2)),
      );

      final persistedInput = state.farm!.toJson();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await preferences.reload();
      state = WorkspaceController(
        sampleRepository: await SampleFarmRepository.open(),
        cloud: null,
      );
      await tester.pumpWidget(FarmTwinApp(workspace: state));
      await tester.pumpAndSettle();
      expect(
        state.farm,
        isNull,
        reason:
            'Saved sample data must still require explicit workspace selection.',
      );
      await tester.tap(find.text('Load Sample Farm'));
      await settledUntil(() => state.farm != null && !state.busy);
      expect(state.farm!.toJson(), persistedInput);
      expect(
        await state.repository!
            .watchEntities(state.farm!.id, EntityKind.optimizationRuns)
            .first,
        hasLength(1),
      );
      final simulations = await state.repository!
          .watchEntities(state.farm!.id, EntityKind.simulationRuns)
          .first;
      expect(simulations, hasLength(1));
      expect(
        ((simulations.single.data['result'] as Map)['alternative']
            as Map)['mean'],
        risk.alternative!.mean,
      );
      expect(
        ((simulations.single.data['result'] as Map)['alternative'] as Map)
            .containsKey('samples'),
        isFalse,
      );
    },
  );
}
