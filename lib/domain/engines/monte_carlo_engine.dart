import 'dart:math' as math;
import '../models/farm_models.dart';
import '../models/results.dart';
import 'financial_engine.dart';

class MonteCarloEngine {
  const MonteCarloEngine();
  MonteCarloResult run(
    Farm farm,
    FarmPlan plan, {
    SimulationConfig? config,
    void Function(int, int)? onProgress,
  }) {
    final watch = Stopwatch()..start();
    farm.validate(requireReady: true);
    farm.validatePlan(plan);
    final supplied = config ?? farm.settings.simulation;
    supplied.validate();
    if (supplied.iterations * (farm.fields.length + farm.crops.length) >
        maximumSimulationFactorDraws) {
      throw const SimulationFailure(
        'This simulation exceeds the supported on-device work budget. Reduce the iteration count.',
      );
    }
    final baseline = const FinancialEngine().evaluate(
      farm,
      plan,
      validate: false,
    );
    final random = math.Random(supplied.seed);
    double normal() {
      // Box-Muller avoids zero logarithms without a farm-specific constant.
      final u = 1 - random.nextDouble(), v = random.nextDouble();
      return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
    }

    double factor(double coefficientOfVariation, double z) {
      final sigma = math.sqrt(
        math.log(1 + coefficientOfVariation * coefficientOfVariation),
      );
      final value = math.exp(sigma * z - sigma * sigma / 2);
      if (!value.isFinite) {
        throw const SimulationFailure(
          'Uncertainty assumptions exceed the supported numeric range.',
        );
      }
      return value;
    }

    final weatherShared = math.sqrt(supplied.weatherCorrelation),
        weatherSpecific = math.sqrt(1 - supplied.weatherCorrelation);
    final marketShared = math.sqrt(supplied.marketCorrelation),
        marketSpecific = math.sqrt(1 - supplied.marketCorrelation);
    final waterLimits = farm.constraints
        .where(
          (c) =>
              c.kind == ConstraintKind.maxWater &&
              c.mode != ConstraintMode.disabled,
        )
        .map((c) => c.limit)
        .toList();
    final waterBudget = waterLimits.isEmpty
        ? baseline.waterUsage
        : waterLimits.reduce(math.min);
    final samples = <double>[];
    var mean = 0.0, m2 = 0.0, positive = 0, negative = 0;
    for (var iteration = 0; iteration < supplied.iterations; iteration++) {
      final weather = normal(), market = normal();
      final fertilizerFactor = factor(supplied.fertilizerVolatility, normal());
      final fuelFactor = factor(supplied.fuelVolatility, normal());
      // Favorable shared weather improves yields and water availability together.
      final availableWater =
          waterBudget * factor(supplied.waterVolatility, weather);
      final waterYieldFactor = baseline.waterUsage <= 0
          ? 1.0
          : math.min(1.0, availableWater / baseline.waterUsage);
      // Drawing every crop and field before reading assignments gives paired
      // plans common random numbers even when their crop combinations differ.
      final cropPrices = <String, double>{
        for (final crop in farm.crops)
          crop.id: factor(
            crop.priceVolatility,
            marketShared * market + marketSpecific * normal(),
          ),
      };
      final fieldWeather = <String, double>{
        for (final field in farm.fields)
          field.id: weatherShared * weather + weatherSpecific * normal(),
      };
      var revenue = 0.0;
      for (final row in baseline.fields) {
        final crop = farm.crop(row.cropId);
        final priceFactor = cropPrices[crop.id]!;
        final yieldFactor = factor(
          crop.yieldVolatility,
          fieldWeather[row.fieldId]!,
        );
        // Irrigation shortages affect crops with an irrigation requirement.
        revenue +=
            row.revenue *
            priceFactor *
            yieldFactor *
            (crop.waterPerAcre > 0 ? waterYieldFactor : 1);
      }
      final fertilizer =
          baseline.costBreakdown['fertilizer']! * (fertilizerFactor - 1);
      final fuel = baseline.costBreakdown['fuel']! * (fuelFactor - 1);
      final equipment =
          random.nextDouble() < supplied.equipmentFailureProbability
          ? supplied.equipmentFailureCost
          : 0.0;
      final cash =
          revenue -
          baseline.operatingExpense -
          baseline.debtService -
          fertilizer -
          fuel -
          equipment;
      if (!cash.isFinite) {
        throw const SimulationFailure(
          'Simulation exceeded the supported numeric range.',
        );
      }
      samples.add(cash);
      final delta = cash - mean;
      mean += delta / (iteration + 1);
      m2 += delta * (cash - mean);
      if (!m2.isFinite || !mean.isFinite) {
        throw const SimulationFailure(
          'Simulation moments exceed the supported numeric range.',
        );
      }
      if (cash > 0) positive++;
      if (cash < 0) negative++;
      if ((iteration + 1) % 256 == 0) {
        onProgress?.call(iteration + 1, supplied.iterations);
      }
    }
    final sorted = samples.toList()..sort();
    double quantile(double probability) {
      final index = (sorted.length - 1) * probability;
      final lo = index.floor(), hi = index.ceil();
      return sorted[lo] + (sorted[hi] - sorted[lo]) * (index - lo);
    }

    watch.stop();
    onProgress?.call(supplied.iterations, supplied.iterations);
    return MonteCarloResult(
      mean: mean,
      median: quantile(.5),
      standardDeviation: math.sqrt(math.max(0, m2 / (samples.length - 1))),
      p05: quantile(.05),
      p25: quantile(.25),
      p75: quantile(.75),
      p95: quantile(.95),
      positiveCashProbability: positive / samples.length,
      negativeCashProbability: negative / samples.length,
      samples: samples,
      iterations: supplied.iterations,
      seed: supplied.seed,
      elapsedMicroseconds: watch.elapsedMicroseconds,
    );
  }
}
