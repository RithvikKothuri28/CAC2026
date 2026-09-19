import 'package:farmtwin/domain/engines/optimization_engine.dart';
import 'package:farmtwin/domain/models/evaluated_plan.dart';
import 'package:farmtwin/domain/models/farm.dart';
import 'package:farmtwin/domain/models/farm_constraint.dart';
import 'package:farmtwin/domain/models/farm_field.dart';
import 'package:farmtwin/domain/models/optimization_result.dart';
import 'package:farmtwin/domain/models/optimization_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_farm.dart';

/// Guards the competition demo.
///
/// The demo has to hold two properties at once: the starting farm must be
/// genuinely vulnerable, and the improvement must be something the engine
/// actually computes. These tests fail if the dataset drifts away from
/// either, so a demo can never quietly stop demonstrating anything.
void main() {
  group('dataset', () {
    test('loads with the documented shape', () {
      final Farm farm = loadDemoFarm();

      expect(farm.fields, hasLength(6));
      expect(farm.cropProfiles, hasLength(5));
      expect(farm.totalAcres, 900);
      expect(farm.planYear, 2026);
      expect(farm.hasCompleteCurrentAllocation, isTrue);
    });

    test('is labelled as a demonstration rather than a real operation', () {
      expect(loadDemoFarm().location.toLowerCase(), contains('demonstration'));
    });

    test('every field carries the history rotation checking needs', () {
      for (final FarmField field in loadDemoFarm().fields) {
        expect(
          field.cropHistory,
          hasLength(2),
          reason: '${field.id} needs two seasons of history',
        );
        expect(field.currentCropId, isNotNull);
        expect(field.acres, greaterThan(0));
      }
    });

    test('mixes irrigated and dryland ground', () {
      final Farm farm = loadDemoFarm();
      expect(farm.irrigatedAcres, 635);
      expect(farm.totalAcres - farm.irrigatedAcres, 265);
    });

    test('carries both hard limits and softer preferences', () {
      final Farm farm = loadDemoFarm();
      expect(farm.hardConstraints, hasLength(5));
      expect(farm.preferenceConstraints, hasLength(4));
    });
  });

  group('the starting farm is genuinely in trouble', () {
    late EvaluatedPlan current;

    setUp(() {
      current = const OptimizationEngine()
          .run(farm: loadDemoFarm(), settings: OptimizationSettings.balanced())
          .currentPlan!;
    });

    test('it makes an operating profit but cannot cover its debt', () {
      expect(current.financials.operatingIncome, greaterThan(0));
      expect(current.financials.cashAfterDebtService, lessThan(0));
      expect(current.financials.debtServiceCoverageRatio, lessThan(1.0));
    });

    test('it is dangerously concentrated in one crop', () {
      expect(current.financials.maxCropConcentration, greaterThan(0.7));
      expect(current.financials.acresByCrop['corn'], 635);
    });

    test('it satisfies none of the farmer own preferences', () {
      expect(current.preferenceConstraintCount, 4);
      expect(current.satisfiedPreferenceCount, 0);
    });

    test('it breaks the rotation rule the farmer set', () {
      expect(current.isFeasible, isFalse);
      expect(
        current.hardViolations.single.type,
        ConstraintType.rotationRequired,
      );
    });
  });

  group('the optimiser finds a real improvement', () {
    late OptimizationResult result;

    setUp(() {
      result = const OptimizationEngine().run(
        farm: loadDemoFarm(),
        settings: OptimizationSettings.balanced(),
      );
    });

    test('it turns a cash shortfall into a surplus', () {
      final EvaluatedPlan best = result.recommendedPlan!;

      expect(result.currentPlan!.financials.cashAfterDebtService, lessThan(0));
      expect(best.financials.cashAfterDebtService, greaterThan(0));
      expect(result.cashImprovement, greaterThan(80000));
    });

    test('it satisfies every preference the current plan misses', () {
      expect(result.recommendedPlan!.satisfiedPreferenceCount, 4);
      expect(result.recommendedPlan!.preferenceConstraintCount, 4);
    });

    test('it does so without exceeding the water the farm has', () {
      expect(
        result.recommendedPlan!.resources.waterAcreInches,
        lessThanOrEqualTo(7800),
      );
    });

    test('it cuts applied nitrogen substantially', () {
      expect(
        result.recommendedPlan!.resources.nitrogenLbs,
        lessThan(result.currentPlan!.resources.nitrogenLbs * 0.5),
      );
    });

    test('it offers a real tradeoff rather than one answer', () {
      expect(result.paretoFront.length, greaterThan(5));
      expect(
        result.representatives.keys,
        containsAll(<RepresentativePlan>[
          RepresentativePlan.balanced,
          RepresentativePlan.profitFocus,
          RepresentativePlan.resourceEfficient,
          RepresentativePlan.resilienceFocus,
        ]),
      );

      // The frugal end of the frontier really is drier and really does cost
      // money — if those two were not both true there would be no tradeoff
      // to explore.
      final EvaluatedPlan frugal =
          result.representatives[RepresentativePlan.resourceEfficient]!;
      final EvaluatedPlan profitable =
          result.representatives[RepresentativePlan.profitFocus]!;

      expect(
        frugal.resources.waterAcreInches,
        lessThan(profitable.resources.waterAcreInches),
      );
      expect(
        frugal.financials.cashAfterDebtService,
        lessThan(profitable.financials.cashAfterDebtService),
      );
    });

    test('it names the water limit as what is holding the farm back', () {
      expect(
        result.bindingConstraints.first.constraint.type,
        ConstraintType.maxWaterAcreInches,
      );
    });

    test('it runs fast enough to feel instant on a phone', () {
      // A demo that stalls is a demo that fails. The whole search is a few
      // thousand additions over a precomputed cost table.
      expect(result.stats.runtime.inMilliseconds, lessThan(2000));
    });
  });
}
