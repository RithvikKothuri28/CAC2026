import 'dart:math' as math;

import '../models/crop_profile.dart';
import '../models/evaluated_plan.dart';
import '../models/farm.dart';
import '../models/field_crop_economics.dart';
import '../models/simulation_result.dart';
import '../models/uncertainty_model.dart';

/// Measures how a farm plan behaves across thousands of simulated seasons.
///
/// Expected value says what an average year looks like. A farm never gets an
/// average year, so this engine re-prices the same plan under repeated draws
/// of weather, commodity prices and input costs, and reports the shape of the
/// distribution that comes out.
///
/// Every run is reproducible: identical plan, uncertainty and seed produce an
/// identical distribution, which is what makes the demo repeatable and the
/// tests meaningful.
class MonteCarloEngine {
  const MonteCarloEngine();

  /// Simulates [plan] for [trials] seasons.
  ///
  /// The plan is held fixed — the farmer already committed to the allocation,
  /// and this asks what the weather and the market do to it. Changes to the
  /// plan itself belong to the scenario engine, which re-optimises.
  SimulationResult run({
    required Farm farm,
    required EvaluatedPlan plan,
    required UncertaintyModel uncertainty,
    required int seed,
    int trials = 5000,
    String? label,
  }) {
    final math.Random random = math.Random(seed);
    final _NormalSampler normal = _NormalSampler(random);

    // Shocks are drawn for every crop the farm could grow, not just the ones
    // this plan uses, and always in sorted order. Both details matter: the
    // fixed order makes a run reproducible, and the fixed count makes two
    // different plans consume the same draw sequence, which is what lets
    // [compare] hold the weather constant between them.
    final List<String> cropIds =
        farm.cropProfiles.map((CropProfile c) => c.id).toList()..sort();

    final double fixedExpense = farm.totalFixedExpense;
    final double debtService = farm.totalDebtService;
    final List<FieldCropEconomics> cells = plan.cells;

    final List<double> samples = List<double>.filled(trials, 0);

    for (int t = 0; t < trials; t++) {
      // One shared growing season, then crop-specific variation on top.
      final double weather = normal.next() * uncertainty.weatherYieldStdDev;

      final Map<String, double> yieldFactor = <String, double>{};
      final Map<String, double> priceFactor = <String, double>{};

      for (final String cropId in cropIds) {
        final double idiosyncratic =
            normal.next() * uncertainty.cropYieldStdDev;
        yieldFactor[cropId] = (1 + weather + idiosyncratic).clamp(
          uncertainty.minYieldFactor,
          uncertainty.maxYieldFactor,
        );

        // A short crop across the region tends to lift price. Without this
        // partial hedge the model would overstate how bad a dry year is.
        final double priceShock = normal.next() * uncertainty.cropPriceStdDev;
        final double hedge = -weather * uncertainty.priceYieldElasticity;
        priceFactor[cropId] = (1 + priceShock + hedge).clamp(
          uncertainty.minPriceFactor,
          uncertainty.maxPriceFactor,
        );
      }

      final double fertilizerFactor = math.max(
        0.0,
        1 + normal.next() * uncertainty.fertilizerPriceStdDev,
      );
      final double fuelFactor = math.max(
        0.0,
        1 + normal.next() * uncertainty.fuelPriceStdDev,
      );

      double revenue = 0;
      double variableCost = 0;

      for (final FieldCropEconomics cell in cells) {
        final double y = yieldFactor[cell.cropId] ?? 1;
        final double p = priceFactor[cell.cropId] ?? 1;
        revenue += cell.revenue * y * p;

        variableCost +=
            cell.seedCost +
            cell.chemicalCost +
            cell.laborCost +
            cell.waterCost +
            cell.equipmentCost +
            (cell.fertilizerCost * fertilizerFactor) +
            (cell.fuelCost * fuelFactor);
      }

      // Drawn last so the number of draws per trial stays constant, keeping
      // the sequence aligned across plans compared on the same seed.
      final bool equipmentFailure =
          random.nextDouble() < uncertainty.equipmentFailureProbability;
      final double unplannedCost = equipmentFailure
          ? uncertainty.equipmentFailureCost
          : 0;

      samples[t] =
          revenue - variableCost - fixedExpense - debtService - unplannedCost;
    }

    samples.sort();

    return SimulationResult(
      planLabel: label ?? (plan.label.isEmpty ? plan.signature : plan.label),
      trials: trials,
      seed: seed,
      sortedSamples: samples,
      deterministicValue: plan.financials.cashAfterDebtService,
    );
  }

  /// Simulates two plans under identical draws.
  ///
  /// Reusing the seed gives both plans the same weather and the same markets,
  /// so the difference between the distributions is caused by the plans and
  /// not by the luck of the draw. Comparing independently seeded runs would
  /// bury a real difference under sampling noise.
  ({SimulationResult current, SimulationResult candidate}) compare({
    required Farm farm,
    required EvaluatedPlan currentPlan,
    required EvaluatedPlan candidatePlan,
    required UncertaintyModel uncertainty,
    required int seed,
    int trials = 5000,
  }) => (
    current: run(
      farm: farm,
      plan: currentPlan,
      uncertainty: uncertainty,
      seed: seed,
      trials: trials,
      label: 'Current Plan',
    ),
    candidate: run(
      farm: farm,
      plan: candidatePlan,
      uncertainty: uncertainty,
      seed: seed,
      trials: trials,
      label: candidatePlan.label.isEmpty
          ? 'FarmTwin Plan'
          : candidatePlan.label,
    ),
  );
}

/// Standard normal draws via the Box-Muller transform.
///
/// Box-Muller produces two independent normals per pair of uniforms; the
/// spare is cached so no draw is wasted and the consumption of the underlying
/// random sequence stays predictable.
class _NormalSampler {
  _NormalSampler(this._random);

  final math.Random _random;
  double? _spare;

  double next() {
    final double? cached = _spare;
    if (cached != null) {
      _spare = null;
      return cached;
    }

    // Reject exact zero: log(0) is undefined.
    double u1 = _random.nextDouble();
    while (u1 <= 0) {
      u1 = _random.nextDouble();
    }
    final double u2 = _random.nextDouble();

    final double magnitude = math.sqrt(-2 * math.log(u1));
    final double angle = 2 * math.pi * u2;

    _spare = magnitude * math.sin(angle);
    return magnitude * math.cos(angle);
  }
}
