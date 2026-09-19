import 'package:farmtwin/domain/engines/constraint_engine.dart';
import 'package:farmtwin/domain/engines/optimization_engine.dart';
import 'package:farmtwin/domain/engines/pareto_engine.dart';
import 'package:farmtwin/domain/models/evaluated_plan.dart';
import 'package:farmtwin/domain/models/farm.dart';
import 'package:farmtwin/domain/models/farm_constraint.dart';
import 'package:farmtwin/domain/models/farm_field.dart';
import 'package:farmtwin/domain/models/objective.dart';
import 'package:farmtwin/domain/models/optimization_result.dart';
import 'package:farmtwin/domain/models/optimization_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_farm.dart';

/// The invariants an optimisation run must never break.
///
/// These are the load-bearing guarantees: if any of them fails, FarmTwin is
/// showing a farmer a plan that is not actually valid.
void main() {
  const OptimizationEngine engine = OptimizationEngine();
  const ConstraintEngine constraints = ConstraintEngine();
  const ParetoEngine pareto = ParetoEngine();

  late Farm farm;
  late OptimizationResult result;

  setUp(() {
    farm = loadDemoFarm();
    result = engine.run(farm: farm, settings: OptimizationSettings.balanced());
  });

  group('invariant: plan structure', () {
    test('every plan assigns exactly one crop to every field', () {
      final List<EvaluatedPlan> plans = <EvaluatedPlan>[
        ...result.paretoFront,
        ...result.representatives.values,
        ?result.recommendedPlan,
      ];
      expect(plans, isNotEmpty);

      for (final EvaluatedPlan plan in plans) {
        expect(plan.allocation.fieldCount, farm.fields.length);
        for (final FarmField field in farm.fields) {
          expect(
            plan.allocation.cropFor(field.id),
            isNotNull,
            reason: '${field.id} unassigned in ${plan.signature}',
          );
        }
      }
    });

    test('every selected crop is agronomically legal on its field', () {
      for (final EvaluatedPlan plan in result.paretoFront) {
        for (final FarmField field in farm.fields) {
          final String cropId = plan.allocation.cropFor(field.id)!;
          expect(
            constraints.isPairingAllowed(
              farm: farm,
              field: field,
              crop: farm.crop(cropId)!,
              enforceRotation: true,
            ),
            isTrue,
            reason: '$cropId is not legal on ${field.id}',
          );
        }
      }
    });

    test('planned acreage always equals the farm acreage', () {
      for (final EvaluatedPlan plan in result.paretoFront) {
        expect(plan.financials.totalAcres, closeTo(farm.totalAcres, 1e-9));
        expect(plan.resources.totalAcres, closeTo(farm.totalAcres, 1e-9));
      }
    });

    test('revenue reconciles against the per-crop breakdown on every plan', () {
      for (final EvaluatedPlan plan in result.paretoFront) {
        final double byCrop = plan.financials.revenueByCrop.values.fold<double>(
          0,
          (double sum, double r) => sum + r,
        );
        expect(byCrop, closeTo(plan.financials.totalRevenue, 1e-6));
      }
    });
  });

  group('invariant: feasibility', () {
    test('no returned plan violates a hard constraint', () {
      final List<EvaluatedPlan> plans = <EvaluatedPlan>[
        ...result.paretoFront,
        ...result.representatives.values,
        ?result.recommendedPlan,
      ];

      for (final EvaluatedPlan plan in plans) {
        expect(
          plan.hardViolations,
          isEmpty,
          reason: '${plan.signature} broke ${plan.hardViolations}',
        );
        expect(plan.isFeasible, isTrue);
      }
    });

    test('feasible plans stay inside every numeric ceiling', () {
      for (final EvaluatedPlan plan in result.paretoFront) {
        expect(plan.resources.waterAcreInches, lessThanOrEqualTo(7800 + 1e-6));
        expect(plan.resources.nitrogenLbs, lessThanOrEqualTo(135000 + 1e-6));
        expect(
          plan.financials.totalOperatingExpense,
          lessThanOrEqualTo(640000 + 1e-6),
        );
        expect(plan.financials.cropCount, greaterThanOrEqualTo(3));
      }
    });

    test('the baseline is evaluated even though it breaks a hard rule', () {
      final EvaluatedPlan? current = result.currentPlan;
      expect(current, isNotNull);

      // The farm's own plan repeats corn on North Quarter, so it could never
      // be produced by the search — but the farmer still needs to see it.
      expect(current!.isFeasible, isFalse);
      expect(
        current.hardViolations.single.type,
        ConstraintType.rotationRequired,
      );
    });
  });

  group('invariant: Pareto frontier', () {
    test('the frontier contains no dominated plan', () {
      final List<ObjectiveType> objectives =
          result.settings.weights.activeObjectives;

      for (final EvaluatedPlan a in result.paretoFront) {
        for (final EvaluatedPlan b in result.paretoFront) {
          if (identical(a, b)) continue;
          expect(
            pareto.dominates(a, b, objectives),
            isFalse,
            reason: '${a.signature} dominates ${b.signature}',
          );
        }
      }
    });

    test('the frontier holds distinct allocations', () {
      final Set<String> signatures = result.paretoFront
          .map((EvaluatedPlan p) => p.signature)
          .toSet();
      expect(signatures, hasLength(result.paretoFront.length));
    });

    test('the frontier is never larger than the display cap', () {
      expect(
        result.paretoFront.length,
        lessThanOrEqualTo(result.settings.maxParetoPlans),
      );
    });
  });

  group('invariant: counters are measured, not decorative', () {
    test('the reported counters agree with each other', () {
      final OptimizationStats stats = result.stats;

      expect(stats.allocationSpace, 15625);
      expect(stats.candidatesGenerated, 1728);
      expect(stats.candidatesPruned, 15625 - 1728);
      expect(stats.plansEvaluated, stats.candidatesGenerated);
      expect(stats.feasiblePlans, lessThanOrEqualTo(stats.plansEvaluated));
      expect(stats.paretoPlans, lessThanOrEqualTo(stats.feasiblePlans));
      expect(stats.wasSampled, isFalse);
      expect(stats.runtime, greaterThan(Duration.zero));
    });
  });

  group('invariant: determinism', () {
    test('identical inputs produce an identical run', () {
      final OptimizationResult repeat = engine.run(
        farm: loadDemoFarm(),
        settings: OptimizationSettings.balanced(),
      );

      expect(
        repeat.recommendedPlan!.signature,
        result.recommendedPlan!.signature,
      );
      expect(
        repeat.paretoFront.map((EvaluatedPlan p) => p.signature).toList(),
        result.paretoFront.map((EvaluatedPlan p) => p.signature).toList(),
      );
      expect(repeat.stats.feasiblePlans, result.stats.feasiblePlans);
      expect(repeat.stats.paretoPlans, result.stats.paretoPlans);
      expect(
        repeat.recommendedPlan!.financials.cashAfterDebtService,
        result.recommendedPlan!.financials.cashAfterDebtService,
      );
    });
  });

  group('binding constraints', () {
    test('the water limit is identified as binding', () {
      final BindingConstraint water = result.bindingConstraints.firstWhere(
        (BindingConstraint b) =>
            b.constraint.type == ConstraintType.maxWaterAcreInches,
      );

      expect(water.reason, BindingReason.blockedBetterPlans);
      expect(water.plansBlocked, greaterThan(0));
      expect(water.utilisation, greaterThan(0.95));
      // Plans worth more than the recommendation were rejected by the water
      // ceiling alone, which is what makes it genuinely binding.
      expect(
        water.bestBlockedProfit,
        greaterThan(result.recommendedPlan!.financials.cashAfterDebtService),
      );
    });
  });

  group('invariant: a binding constraint changes the feasible set', () {
    test('tightening the water limit produces a different, drier plan', () {
      final Farm tighter = farm.copyWith(
        constraints: farm.constraints
            .map(
              (FarmConstraint c) => c.type == ConstraintType.maxWaterAcreInches
                  ? c.copyWith(numericValue: 5200)
                  : c,
            )
            .toList(),
      );

      final OptimizationResult restricted = engine.run(
        farm: tighter,
        settings: OptimizationSettings.balanced(),
      );

      expect(
        restricted.stats.feasiblePlans,
        lessThan(result.stats.feasiblePlans),
      );
      expect(
        restricted.recommendedPlan!.signature,
        isNot(result.recommendedPlan!.signature),
      );
      expect(
        restricted.recommendedPlan!.resources.waterAcreInches,
        lessThanOrEqualTo(5200 + 1e-6),
      );
      // Less water available means less income. That is the tradeoff, and the
      // engine must show it rather than hide it.
      expect(
        restricted.recommendedPlan!.financials.cashAfterDebtService,
        lessThan(result.recommendedPlan!.financials.cashAfterDebtService),
      );
    });

    test('relaxing the water limit unlocks the plans it was blocking', () {
      final Farm looser = farm.copyWith(
        constraints: farm.constraints
            .map(
              (FarmConstraint c) => c.type == ConstraintType.maxWaterAcreInches
                  ? c.copyWith(numericValue: 12000)
                  : c,
            )
            .toList(),
      );

      final OptimizationResult relaxed = engine.run(
        farm: looser,
        settings: OptimizationSettings.balanced(),
      );

      expect(
        relaxed.stats.feasiblePlans,
        greaterThan(result.stats.feasiblePlans),
      );
      expect(
        relaxed.recommendedPlan!.financials.cashAfterDebtService,
        greaterThan(result.recommendedPlan!.financials.cashAfterDebtService),
      );
    });
  });

  group('objective weights steer the recommendation', () {
    test('a profit-only farmer gets the highest-cash feasible plan', () {
      final OptimizationResult profitRun = engine.run(
        farm: farm,
        settings: OptimizationSettings(
          weights: ObjectiveWeights.single(ObjectiveType.expectedProfit),
        ),
      );

      for (final EvaluatedPlan plan in profitRun.paretoFront) {
        expect(
          plan.financials.cashAfterDebtService,
          lessThanOrEqualTo(
            profitRun.recommendedPlan!.financials.cashAfterDebtService + 1e-6,
          ),
        );
      }
    });

    test('a water-only farmer gets a drier plan than a profit-only one', () {
      final OptimizationResult waterRun = engine.run(
        farm: farm,
        settings: OptimizationSettings(
          weights: ObjectiveWeights.single(ObjectiveType.waterEfficiency),
        ),
      );
      final OptimizationResult profitRun = engine.run(
        farm: farm,
        settings: OptimizationSettings(
          weights: ObjectiveWeights.single(ObjectiveType.expectedProfit),
        ),
      );

      expect(
        waterRun.recommendedPlan!.resources.waterAcreInches,
        lessThan(profitRun.recommendedPlan!.resources.waterAcreInches),
      );
    });
  });

  group('no feasible plan', () {
    test('an impossible water limit reports honestly instead of guessing', () {
      final Farm impossible = farm.copyWith(
        constraints: farm.constraints
            .map(
              (FarmConstraint c) => c.type == ConstraintType.maxWaterAcreInches
                  ? c.copyWith(numericValue: 0)
                  : c,
            )
            .toList(),
      );

      final OptimizationResult none = engine.run(
        farm: impossible,
        settings: OptimizationSettings.balanced(),
      );

      expect(none.hasNoFeasiblePlan, isTrue);
      expect(none.recommendedPlan, isNull);
      expect(none.paretoFront, isEmpty);
      expect(none.representatives, isEmpty);
      expect(none.cashImprovement, isNull);
      // The baseline is still reported, so the farmer sees where they stand.
      expect(none.currentPlan, isNotNull);
    });
  });
}
