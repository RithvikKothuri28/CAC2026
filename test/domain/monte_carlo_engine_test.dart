import 'package:farmtwin/domain/engines/monte_carlo_engine.dart';
import 'package:farmtwin/domain/engines/optimization_engine.dart';
import 'package:farmtwin/domain/models/evaluated_plan.dart';
import 'package:farmtwin/domain/models/farm.dart';
import 'package:farmtwin/domain/models/optimization_result.dart';
import 'package:farmtwin/domain/models/optimization_settings.dart';
import 'package:farmtwin/domain/models/simulation_result.dart';
import 'package:farmtwin/domain/models/uncertainty_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_farm.dart';

void main() {
  const MonteCarloEngine monteCarlo = MonteCarloEngine();

  late Farm farm;
  late EvaluatedPlan currentPlan;
  late EvaluatedPlan optimizedPlan;

  setUp(() {
    farm = loadDemoFarm();
    final OptimizationResult result = const OptimizationEngine().run(
      farm: farm,
      settings: OptimizationSettings.balanced(),
    );
    currentPlan = result.currentPlan!;
    optimizedPlan = result.recommendedPlan!;
  });

  group('invariant: reproducibility', () {
    test('the same plan, model and seed produce an identical distribution', () {
      SimulationResult simulate() => monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: UncertaintyModel.standard(),
        seed: 20260214,
        trials: 2000,
      );

      final SimulationResult first = simulate();
      final SimulationResult second = simulate();

      expect(second.samples, first.samples);
      expect(second.mean, first.mean);
      expect(second.p5, first.p5);
      expect(second.probabilityPositive, first.probabilityPositive);
    });

    test('a different seed produces a different distribution', () {
      final SimulationResult a = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: UncertaintyModel.standard(),
        seed: 1,
        trials: 2000,
      );
      final SimulationResult b = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: UncertaintyModel.standard(),
        seed: 2,
        trials: 2000,
      );

      expect(b.samples, isNot(a.samples));
      // Different draws, same underlying plan: the centres should still land
      // close together.
      expect(b.median, closeTo(a.median, 15000));
    });
  });

  group('invariant: no uncertainty means no spread', () {
    test('every trial returns the deterministic result exactly', () {
      final SimulationResult result = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: UncertaintyModel.none(),
        seed: 99,
        trials: 500,
      );

      final double expected = optimizedPlan.financials.cashAfterDebtService;

      expect(result.standardDeviation, closeTo(0, 1e-6));
      expect(result.mean, closeTo(expected, 1e-6));
      expect(result.median, closeTo(expected, 1e-6));
      expect(result.p5, closeTo(expected, 1e-6));
      expect(result.p95, closeTo(expected, 1e-6));
    });
  });

  group('distribution shape', () {
    late SimulationResult result;

    setUp(() {
      result = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: UncertaintyModel.standard(),
        seed: 20260214,
        trials: 4000,
      );
    });

    test('percentiles are monotonically ordered', () {
      expect(result.minimum, lessThanOrEqualTo(result.p5));
      expect(result.p5, lessThanOrEqualTo(result.p25));
      expect(result.p25, lessThanOrEqualTo(result.median));
      expect(result.median, lessThanOrEqualTo(result.p75));
      expect(result.p75, lessThanOrEqualTo(result.p95));
      expect(result.p95, lessThanOrEqualTo(result.maximum));
    });

    test('probabilities are complementary and in range', () {
      expect(result.probabilityPositive, inInclusiveRange(0, 1));
      expect(
        result.probabilityPositive + result.probabilityNegative,
        closeTo(1, 1e-9),
      );
    });

    test('expected shortfall sits below the fifth percentile', () {
      // The mean of the worst 5% of years must be worse than the boundary of
      // that same tail.
      expect(result.expectedShortfall(), lessThanOrEqualTo(result.p5));
    });

    test('the histogram accounts for every sample', () {
      final int total = result
          .histogram(buckets: 24)
          .fold<int>(0, (int sum, int count) => sum + count);
      expect(total, result.trials);
    });

    test('the persisted summary omits the raw samples', () {
      final Map<String, dynamic> summary = result.toSummaryJson();
      expect(summary.containsKey('samples'), isFalse);
      expect(summary['trials'], result.trials);
      expect(summary['seed'], result.seed);
    });
  });

  group('comparing two plans', () {
    test('both plans face the same simulated seasons', () {
      final ({SimulationResult candidate, SimulationResult current}) paired =
          monteCarlo.compare(
            farm: farm,
            currentPlan: currentPlan,
            candidatePlan: optimizedPlan,
            uncertainty: UncertaintyModel.standard(),
            seed: 20260214,
            trials: 2000,
          );

      // Shocks are drawn for every crop the farm grows, not just the ones a
      // plan uses, so the two runs consume the same random sequence and the
      // difference between them is caused by the plans alone.
      final SimulationResult solo = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: UncertaintyModel.standard(),
        seed: 20260214,
        trials: 2000,
      );
      expect(paired.candidate.samples, solo.samples);
    });

    test('the optimised plan carries less downside than the current one', () {
      final ({SimulationResult candidate, SimulationResult current}) paired =
          monteCarlo.compare(
            farm: farm,
            currentPlan: currentPlan,
            candidatePlan: optimizedPlan,
            uncertainty: UncertaintyModel.standard(),
            seed: 20260214,
            trials: 4000,
          );

      expect(paired.candidate.median, greaterThan(paired.current.median));
      expect(paired.candidate.p5, greaterThan(paired.current.p5));
      expect(
        paired.candidate.probabilityPositive,
        greaterThan(paired.current.probabilityPositive),
      );
      // The demo farm's existing plan is more likely than not to end the year
      // short, and the optimised plan flips that.
      expect(paired.current.probabilityPositive, lessThan(0.5));
      expect(paired.candidate.probabilityPositive, greaterThan(0.5));
    });
  });

  group('shocks move the distribution the right way', () {
    test('a higher fertiliser price lowers simulated cash', () {
      final UncertaintyModel base = UncertaintyModel.none();
      final SimulationResult calm = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: base,
        seed: 5,
        trials: 1500,
      );
      final SimulationResult volatile = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: base.copyWith(fertilizerPriceStdDev: 0.30),
        seed: 5,
        trials: 1500,
      );

      expect(volatile.standardDeviation, greaterThan(calm.standardDeviation));
      expect(volatile.p5, lessThan(calm.p5));
    });

    test('an equipment failure risk only ever costs money', () {
      final SimulationResult withRisk = monteCarlo.run(
        farm: farm,
        plan: optimizedPlan,
        uncertainty: const UncertaintyModel(
          weatherYieldStdDev: 0,
          cropYieldStdDev: 0,
          cropPriceStdDev: 0,
          fertilizerPriceStdDev: 0,
          fuelPriceStdDev: 0,
          priceYieldElasticity: 0,
          equipmentFailureProbability: 0.5,
          equipmentFailureCost: 40000,
        ),
        seed: 11,
        trials: 2000,
      );

      final double deterministic =
          optimizedPlan.financials.cashAfterDebtService;

      expect(withRisk.maximum, closeTo(deterministic, 1e-6));
      expect(withRisk.minimum, closeTo(deterministic - 40000, 1e-6));
      expect(withRisk.mean, lessThan(deterministic));
    });
  });
}
