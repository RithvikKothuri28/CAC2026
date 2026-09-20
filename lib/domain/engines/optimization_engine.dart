import 'dart:math' as math;
import '../models/farm_models.dart';
import '../models/results.dart';
import 'financial_engine.dart';
import 'constraint_engine.dart';

/// Deterministic exhaustive search when safe, bounded seeded search otherwise.
/// Scores are normalized against the actual feasible candidate population.
class OptimizationEngine {
  const OptimizationEngine();
  static const _financial = FinancialEngine();
  static const _constraints = ConstraintEngine();

  EvaluatedPlan evaluate(Farm farm, FarmPlan plan, {bool validate = true}) {
    if (validate) {
      farm.validate(requireReady: true);
      farm.validatePlan(plan);
    }
    final financial = _financial.evaluate(farm, plan, validate: false);
    final constraints = _constraints.evaluate(farm, plan, financial);
    // A transparent analytical downside proxy, not a Monte Carlo percentile.
    // Field yields and crop markets use configured shared-factor correlations.
    var independentVariance = 0.0, weatherExposure = 0.0, marketExposure = 0.0;
    final priceExposureByCrop = <String, double>{};
    for (final row in financial.fields) {
      final crop = farm.crop(row.cropId);
      final y = row.revenue * crop.yieldVolatility;
      final p = row.revenue * crop.priceVolatility;
      weatherExposure +=
          y * math.sqrt(farm.settings.simulation.weatherCorrelation);
      priceExposureByCrop.update(crop.id, (v) => v + p, ifAbsent: () => p);
      independentVariance +=
          y * y * (1 - farm.settings.simulation.weatherCorrelation);
    }
    for (final exposure in priceExposureByCrop.values) {
      marketExposure +=
          exposure * math.sqrt(farm.settings.simulation.marketCorrelation);
      independentVariance +=
          exposure *
          exposure *
          (1 - farm.settings.simulation.marketCorrelation);
    }
    final downside = math.sqrt(
      independentVariance +
          weatherExposure * weatherExposure +
          marketExposure * marketExposure,
    );
    if (!downside.isFinite) {
      throw const OptimizationFailure(
        'Risk assumptions exceed the supported numeric range.',
      );
    }
    return EvaluatedPlan(
      plan: plan,
      financial: financial,
      constraints: constraints,
      objectives: {
        Objective.profit: financial.operatingIncome,
        Objective.resilience: financial.cashAfterDebt - downside,
        Objective.waterEfficiency: -financial.waterUsage,
        Objective.inputEfficiency: -financial.nitrogenUsage,
        Objective.practiceAlignment: constraints.alignment,
        Objective.diversification: 1 - financial.concentration,
      },
    );
  }

  /// Strict Pareto dominance uses all configured objectives with positive weight.
  /// Equal points do not dominate one another; duplicate outcomes collapse.
  static bool dominates(
    Map<Objective, double> a,
    Map<Objective, double> b,
    Iterable<Objective> objectives,
  ) {
    var strict = false;
    for (final objective in objectives) {
      if (a[objective]! < b[objective]! - numericTolerance) return false;
      if (a[objective]! > b[objective]! + numericTolerance) strict = true;
    }
    return strict;
  }

  OptimizationResult run(
    Farm farm, {
    void Function(OptimizationProgress)? onProgress,
  }) {
    final watch = Stopwatch()..start();
    farm.validate(requireReady: true);
    farm.validatePlan(farm.currentPlan);
    final config = farm.settings.optimization;
    if (farm.fields.length > 512 || farm.crops.length > 2048) {
      throw const OptimizationFailure(
        'This farm exceeds the supported on-device model capacity (512 fields, 2,048 crop profiles).',
      );
    }
    final options = farm.fields
        .map(
          (field) =>
              field.compatibleCropIds
                  .where(
                    (id) =>
                        !farm.crop(id).requiresIrrigation || field.irrigated,
                  )
                  .toList()
                ..sort(),
        )
        .toList();
    var searchSpace = BigInt.one;
    for (var i = 0; i < options.length; i++) {
      if (options[i].isEmpty) {
        throw OptimizationFailure(
          'No compatible crop is available for ${farm.fields[i].name}.',
        );
      }
      searchSpace *= BigInt.from(options[i].length);
    }
    // Bound retained per-field results, in addition to user-selected limits.
    // This is a computational safety bound, not a farm assumption.
    final safeCandidateLimit = math.max(1, 2000000 ~/ farm.fields.length);
    final exhaustive =
        searchSpace <=
        BigInt.from(math.min(config.exhaustiveLimit, safeCandidateLimit));
    final budget = exhaustive
        ? searchSpace.toInt()
        : math.min(config.candidateLimit, safeCandidateLimit);
    final feasible = <EvaluatedPlan>[];
    final seen = <String>{};
    final minima = <Objective, double>{
      for (final o in Objective.values) o: double.infinity,
    };
    final maxima = <Objective, double>{
      for (final o in Objective.values) o: double.negativeInfinity,
    };
    var generated = 0, evaluated = 0, pruned = 0;
    final current = evaluate(farm, farm.currentPlan, validate: false);
    final hardRotation = farm.constraints.any(
      (r) => r.kind == ConstraintKind.rotation && r.mode == ConstraintMode.hard,
    );
    final restricted = farm.constraints
        .where(
          (r) =>
              r.kind == ConstraintKind.restrictedInputs &&
              r.mode == ConstraintMode.hard,
        )
        .expand((r) => r.restrictedInputs)
        .toSet();
    bool visit(List<String> allocation) {
      final key = allocation.join('\u001f');
      if (!seen.add(key)) return false;
      generated++;
      for (var i = 0; i < allocation.length; i++) {
        final crop = farm.crop(allocation[i]);
        if ((hardRotation &&
                !_constraints.rotationAllowed(farm, farm.fields[i], crop)) ||
            crop.inputs.any(restricted.contains)) {
          pruned++;
          return true;
        }
      }
      final plan = FarmPlan(
        assignments: {
          for (var i = 0; i < allocation.length; i++)
            farm.fields[i].id: allocation[i],
        },
      );
      final result = evaluate(farm, plan, validate: false);
      evaluated++;
      if (result.constraints.feasible) {
        feasible.add(result);
        for (final objective in Objective.values) {
          minima[objective] = math.min(
            minima[objective]!,
            result.objectives[objective]!,
          );
          maxima[objective] = math.max(
            maxima[objective]!,
            result.objectives[objective]!,
          );
        }
      } else {
        pruned++;
      }
      if (generated % 256 == 0) {
        onProgress?.call(
          OptimizationProgress(
            generated: generated,
            evaluated: evaluated,
            feasible: feasible.length,
          ),
        );
      }
      return true;
    }

    if (exhaustive) {
      final indices = List<int>.filled(options.length, 0);
      for (var n = 0; n < budget; n++) {
        visit(List.generate(options.length, (i) => options[i][indices[i]]));
        for (var i = indices.length - 1; i >= 0; i--) {
          indices[i]++;
          if (indices[i] < options[i].length) break;
          indices[i] = 0;
        }
      }
    } else {
      final random = math.Random(config.seed);
      visit(farm.fields.map((f) => f.currentCropId).toList());
      // Seed the search with per-field objective extrema, then explore a
      // reproducible mixture of neighboring and globally sampled allocations.
      final seeds = <List<String>>[];
      for (final objective in [
        Objective.profit,
        Objective.waterEfficiency,
        Objective.inputEfficiency,
      ]) {
        final allocation = <String>[];
        for (var i = 0; i < farm.fields.length; i++) {
          final field = farm.fields[i];
          final sorted = options[i].toList()
            ..sort((a, b) {
              double metric(String id) {
                final crop = farm.crop(id);
                return switch (objective) {
                  Objective.waterEfficiency => -crop.waterPerAcre,
                  Objective.inputEfficiency => -crop.nitrogenPerAcre,
                  _ =>
                    crop.yieldPerAcre *
                            field.yieldMultiplier *
                            crop.pricePerUnit -
                        crop.costPerAcre,
                };
              }

              final comparison = metric(b).compareTo(metric(a));
              return comparison == 0 ? a.compareTo(b) : comparison;
            });
          allocation.add(sorted.first);
        }
        seeds.add(allocation);
        if (generated < budget) visit(allocation);
      }
      var attempts = 0;
      while (generated < budget && attempts < budget * 8) {
        attempts++;
        List<String> allocation;
        if (attempts.isEven) {
          if (feasible.isNotEmpty) {
            final base = feasible[random.nextInt(feasible.length)].plan;
            allocation = farm.fields
                .map((f) => base.assignments[f.id]!)
                .toList();
          } else {
            allocation = seeds[random.nextInt(seeds.length)].toList();
          }
          final changes = 1 + random.nextInt(farm.fields.length);
          for (var j = 0; j < changes; j++) {
            final i = random.nextInt(options.length);
            allocation[i] = options[i][random.nextInt(options[i].length)];
          }
        } else {
          allocation = options.map((o) => o[random.nextInt(o.length)]).toList();
        }
        visit(allocation);
      }
    }
    final active = config.weights.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList();
    double score(EvaluatedPlan plan) {
      var sum = 0.0;
      for (final objective in active) {
        final span = maxima[objective]! - minima[objective]!;
        final normalized = span <= numericTolerance
            ? 1.0
            : ((plan.objectives[objective]! - minima[objective]!) / span).clamp(
                0.0,
                1.0,
              );
        sum += config.weights[objective]! * normalized;
      }
      return sum;
    }

    final scored = feasible.map((p) => p.withScore(score(p))).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final frontier = <EvaluatedPlan>[];
    var frontierTruncated = false;
    final outcomes = <String>{};
    for (final candidate in scored) {
      final signature = active
          .map((o) => candidate.objectives[o]!.toStringAsPrecision(14))
          .join('|');
      if (!outcomes.add(signature)) continue;
      if (frontier.any(
        (p) => dominates(p.objectives, candidate.objectives, active),
      )) {
        continue;
      }
      frontier.removeWhere(
        (p) => dominates(candidate.objectives, p.objectives, active),
      );
      frontier.add(candidate);
      // This is an explicit approximation if a configured storage bound is
      // reached. Search diagnostics and warnings never claim a complete frontier.
      if (frontier.length > config.frontierLimit) {
        frontier.removeLast();
        frontierTruncated = true;
      }
    }
    final representatives = <String, EvaluatedPlan>{};
    if (scored.isNotEmpty) {
      representatives['Balanced'] = scored.first;
      for (final entry in {
        'Profit focus': Objective.profit,
        'Resource efficient': Objective.waterEfficiency,
        'Resilience focus': Objective.resilience,
      }.entries) {
        representatives[entry.key] = scored.reduce(
          (a, b) =>
              a.objectives[entry.value]! >= b.objectives[entry.value]! ? a : b,
        );
      }
    }
    watch.stop();
    onProgress?.call(
      OptimizationProgress(
        generated: generated,
        evaluated: evaluated,
        feasible: feasible.length,
      ),
    );
    return OptimizationResult(
      current: feasible.isEmpty ? current : current.withScore(score(current)),
      recommended: scored.firstOrNull,
      pareto: frontier,
      representatives: representatives,
      diagnostics: OptimizationDiagnostics(
        searchSpace: searchSpace.toString(),
        strategy: exhaustive ? 'exhaustive' : 'bounded seeded search',
        candidatesGenerated: generated,
        candidatesPruned: pruned,
        plansEvaluated: evaluated,
        feasiblePlans: feasible.length,
        paretoPlans: frontier.length,
        elapsedMicroseconds: watch.elapsedMicroseconds,
        approximate: !exhaustive || frontierTruncated,
      ),
      warnings: [
        if (!exhaustive)
          'The search space exceeds the exhaustive limit. This bounded, seeded search does not guarantee a global optimum.',
        if (frontierTruncated)
          'The configured frontier storage limit was reached. Displayed tradeoffs are a bounded subset; the highest weighted score still uses every evaluated feasible plan.',
        if (feasible.isEmpty)
          'No feasible plan was found. Review hard constraints${exhaustive ? '' : ' or increase the search budget'}.',
        'Resilience is cash after debt minus an analytical one-standard-deviation revenue risk proxy; it is not a simulated cash percentile.',
      ],
    );
  }
}
