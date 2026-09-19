import 'evaluated_plan.dart';
import 'farm_constraint.dart';
import 'optimization_settings.dart';

/// Why a hard constraint is considered to be holding the plan back.
enum BindingReason {
  /// The chosen plan sits at or just under the farmer's limit.
  atLimit,

  /// Higher-scoring candidates existed but this constraint alone rejected
  /// them — relaxing it would genuinely open up better plans.
  blockedBetterPlans,
}

/// A hard constraint that is actively shaping the result.
///
/// This is what lets the assistant answer "which constraint is limiting my
/// profit-focused plan?" from real search data rather than a guess.
class BindingConstraint {
  const BindingConstraint({
    required this.constraint,
    required this.reason,
    required this.utilisation,
    required this.plansBlocked,
    this.bestBlockedProfit,
  });

  final FarmConstraint constraint;
  final BindingReason reason;

  /// Chosen plan's usage as a fraction of the limit. Above 1 for minimum-type
  /// constraints means comfortable headroom rather than a breach.
  final double utilisation;

  /// Candidates this constraint rejected on its own.
  final int plansBlocked;

  /// Best cash-after-debt-service among those solely-blocked candidates.
  final double? bestBlockedProfit;

  @override
  String toString() =>
      'BindingConstraint(${constraint.type.name}, ${reason.name})';
}

/// Counters from the search, surfaced directly in the optimisation UI.
///
/// These are measured, not decorative: every number is produced by the run
/// that just executed.
class OptimizationStats {
  const OptimizationStats({
    required this.allocationSpace,
    required this.candidatesGenerated,
    required this.candidatesPruned,
    required this.plansEvaluated,
    required this.feasiblePlans,
    required this.paretoPlans,
    required this.runtime,
    required this.wasSampled,
  });

  /// `crops ^ fields` — the theoretical size of the allocation space before
  /// any agronomic pruning.
  final int allocationSpace;

  /// Candidates actually enumerated after per-field pruning.
  final int candidatesGenerated;

  /// Removed before enumeration by crop-field incompatibility and rotation.
  final int candidatesPruned;

  /// Candidates fully costed and scored.
  final int plansEvaluated;

  /// Candidates that broke no hard constraint.
  final int feasiblePlans;

  /// Size of the Pareto frontier before display thinning.
  final int paretoPlans;

  final Duration runtime;

  /// True when the space exceeded `maxCandidates` and the generator sampled
  /// rather than enumerated exhaustively.
  final bool wasSampled;

  double get prunedShare =>
      allocationSpace > 0 ? candidatesPruned / allocationSpace : 0;

  double get feasibleShare =>
      plansEvaluated > 0 ? feasiblePlans / plansEvaluated : 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'allocationSpace': allocationSpace,
    'candidatesGenerated': candidatesGenerated,
    'candidatesPruned': candidatesPruned,
    'plansEvaluated': plansEvaluated,
    'feasiblePlans': feasiblePlans,
    'paretoPlans': paretoPlans,
    'runtimeMs': runtime.inMilliseconds,
    'wasSampled': wasSampled,
  };

  @override
  String toString() =>
      'OptimizationStats(generated=$candidatesGenerated, '
      'feasible=$feasiblePlans, pareto=$paretoPlans, '
      '${runtime.inMilliseconds}ms)';
}

/// Everything one optimisation run produced.
class OptimizationResult {
  const OptimizationResult({
    required this.settings,
    required this.stats,
    required this.paretoFront,
    required this.representatives,
    required this.bindingConstraints,
    required this.currentPlan,
    required this.recommendedPlan,
  });

  final OptimizationSettings settings;
  final OptimizationStats stats;

  /// Efficient plans, sorted by expected profit descending.
  final List<EvaluatedPlan> paretoFront;

  /// Named plans for the tradeoff explorer. A key is absent when no feasible
  /// plan could fill that role.
  final Map<RepresentativePlan, EvaluatedPlan> representatives;

  /// Hard constraints shaping the outcome.
  final List<BindingConstraint> bindingConstraints;

  /// The farm's existing plan, evaluated on identical assumptions so the
  /// comparison is like-for-like. Null when the twin has unassigned fields.
  final EvaluatedPlan? currentPlan;

  /// Highest weighted score among feasible plans, or null if none qualified.
  final EvaluatedPlan? recommendedPlan;

  /// True when the search found no plan satisfying every hard constraint.
  bool get hasNoFeasiblePlan => recommendedPlan == null;

  /// Change in cash after debt service between the current and recommended
  /// plans. Null when either side is missing.
  double? get cashImprovement {
    final EvaluatedPlan? current = currentPlan;
    final EvaluatedPlan? best = recommendedPlan;
    if (current == null || best == null) return null;
    return best.financials.cashAfterDebtService -
        current.financials.cashAfterDebtService;
  }

  /// Change in applied irrigation between the current and recommended plans.
  double? get waterChange {
    final EvaluatedPlan? current = currentPlan;
    final EvaluatedPlan? best = recommendedPlan;
    if (current == null || best == null) return null;
    return best.resources.waterAcreInches - current.resources.waterAcreInches;
  }

  @override
  String toString() => 'OptimizationResult($stats)';
}
