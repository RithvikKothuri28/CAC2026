import 'objective.dart';

/// Tuning for one optimisation run.
class OptimizationSettings {
  const OptimizationSettings({
    required this.weights,
    this.maxCandidates = 250000,
    this.maxParetoPlans = 60,
    this.samplingSeed = 20260101,
  });

  OptimizationSettings.balanced()
    : weights = ObjectiveWeights.balanced(),
      maxCandidates = 250000,
      maxParetoPlans = 60,
      samplingSeed = 20260101;

  /// Relative importance of each objective.
  final ObjectiveWeights weights;

  /// Safety ceiling on how many candidates are enumerated.
  ///
  /// The allocation space grows as `crops ^ fields`, so a large farm can
  /// exceed what a phone should evaluate. Past this ceiling the generator
  /// switches to deterministic stride sampling instead of full enumeration,
  /// and the run reports that it did.
  final int maxCandidates;

  /// Cap on how many Pareto-efficient plans are returned to the UI. The
  /// frontier is thinned evenly, never truncated, so the extremes survive.
  final int maxParetoPlans;

  /// Seed for the sampling fallback, so a capped run is still reproducible.
  final int samplingSeed;

  OptimizationSettings copyWith({
    ObjectiveWeights? weights,
    int? maxCandidates,
    int? maxParetoPlans,
  }) => OptimizationSettings(
    weights: weights ?? this.weights,
    maxCandidates: maxCandidates ?? this.maxCandidates,
    maxParetoPlans: maxParetoPlans ?? this.maxParetoPlans,
    samplingSeed: samplingSeed,
  );
}

/// The named plans surfaced on the tradeoff explorer.
enum RepresentativePlan {
  profitFocus('Profit Focus'),
  balanced('Balanced'),
  resourceEfficient('Resource Efficient'),
  resilienceFocus('Resilience Focus');

  const RepresentativePlan(this.label);

  final String label;
}
