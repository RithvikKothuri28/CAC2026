import '../models/crop_allocation.dart';
import '../models/evaluated_plan.dart';
import '../models/farm.dart';
import '../models/farm_constraint.dart';
import '../models/field_crop_economics.dart';
import '../models/objective.dart';
import '../models/optimization_result.dart';
import '../models/optimization_settings.dart';
import 'candidate_generator.dart';
import 'constraint_engine.dart';
import 'financial_engine.dart';
import 'objective_engine.dart';
import 'pareto_engine.dart';
import 'plan_evaluator.dart';

/// FarmTwin's optimiser.
///
/// The run is deterministic from end to end: the same farm and settings
/// always produce the same frontier, the same recommendation and the same
/// counters. No language model participates in any step — the assistant only
/// ever explains what this engine already decided.
///
/// The pipeline is:
/// prune → enumerate → cost → constrain → score → normalise → dominate.
class OptimizationEngine {
  const OptimizationEngine({
    this.generator = const CandidateGenerator(),
    this.evaluator = const PlanEvaluator(),
    this.financial = const FinancialEngine(),
    this.constraints = const ConstraintEngine(),
    this.objectives = const ObjectiveEngine(),
    this.pareto = const ParetoEngine(),
  });

  final CandidateGenerator generator;
  final PlanEvaluator evaluator;
  final FinancialEngine financial;
  final ConstraintEngine constraints;
  final ObjectiveEngine objectives;
  final ParetoEngine pareto;

  /// Objective weights used to pick each representative plan. These are
  /// fixed personalities for the tradeoff explorer, independent of whatever
  /// the farmer set as their own priorities.
  static final Map<RepresentativePlan, ObjectiveWeights> _personalities =
      <RepresentativePlan, ObjectiveWeights>{
        RepresentativePlan.profitFocus: ObjectiveWeights.single(
          ObjectiveType.expectedProfit,
        ),
        RepresentativePlan.resourceEfficient: ObjectiveWeights(
          const <ObjectiveType, double>{
            ObjectiveType.waterEfficiency: 0.55,
            ObjectiveType.inputEfficiency: 0.45,
          },
        ),
        RepresentativePlan.resilienceFocus: ObjectiveWeights(
          const <ObjectiveType, double>{
            ObjectiveType.financialResilience: 0.70,
            ObjectiveType.diversification: 0.30,
          },
        ),
      };

  /// A plan sitting within this fraction of a hard limit is reported as
  /// pressing against it.
  static const double _bindingUtilisationThreshold = 0.98;

  OptimizationResult run({
    required Farm farm,
    required OptimizationSettings settings,
  }) {
    final Stopwatch stopwatch = Stopwatch()..start();

    final CandidateSpace space = generator.prepare(farm);
    final Map<String, Map<String, FieldCropEconomics>> cellTable = financial
        .buildCellTable(
          farm: farm,
          allowedCropIds: <String, List<String>>{
            for (int i = 0; i < space.fields.length; i++)
              space.fields[i].id: space.optionsByField[i],
          },
        );

    // The existing plan is costed on identical assumptions so the comparison
    // is like-for-like, and it is evaluated outside the pruned space because
    // it may well break a rule the search is forbidden to break.
    final EvaluatedPlan? currentPlan = farm.hasCompleteCurrentAllocation
        ? evaluator.evaluate(farm: farm, allocation: farm.currentAllocation)
        : null;

    final List<int> indices = generator.candidateIndices(
      space: space,
      maxCandidates: settings.maxCandidates,
      seed: settings.samplingSeed,
      alwaysInclude: currentPlan?.allocation,
    );

    final List<EvaluatedPlan> feasible = <EvaluatedPlan>[];
    final Map<String, _BlockRecord> blocks = <String, _BlockRecord>{};

    for (final int index in indices) {
      final CropAllocation allocation = space.allocationAt(index);
      final EvaluatedPlan plan = evaluator.evaluate(
        farm: farm,
        allocation: allocation,
        cellTable: cellTable,
      );

      if (plan.isFeasible) {
        feasible.add(plan);
        continue;
      }

      // A plan rejected by exactly one hard constraint is evidence about
      // that constraint: relaxing it, and nothing else, would have let this
      // plan through. That is what makes a constraint genuinely binding.
      final List<ConstraintViolation> hard = plan.hardViolations;
      if (hard.length == 1) {
        final ConstraintViolation only = hard.first;
        final double cash = plan.financials.cashAfterDebtService;
        blocks.update(
          only.constraint.id,
          (_BlockRecord record) => record.observe(cash),
          ifAbsent: () => _BlockRecord(only.constraint)..observe(cash),
        );
      }
    }

    // Normalisation needs a shared scale across everything being compared, so
    // the baseline plan joins the feasible set for scoring purposes only — it
    // never enters the frontier or the recommendation.
    final List<EvaluatedPlan> scoringSet = <EvaluatedPlan>[
      ...feasible,
      ?currentPlan,
    ];
    final List<EvaluatedPlan> scored = objectives.normalize(
      plans: scoringSet,
      weights: settings.weights,
    );

    final List<EvaluatedPlan> scoredFeasible = scored
        .take(feasible.length)
        .toList(growable: false);
    final EvaluatedPlan? scoredCurrent = currentPlan == null
        ? null
        : scored.last;

    final List<EvaluatedPlan> frontier = pareto.frontier(
      plans: scoredFeasible,
      objectives: settings.weights.activeObjectives,
    );

    final EvaluatedPlan? recommended = _bestBy(
      scoredFeasible,
      (EvaluatedPlan p) => p.weightedScore ?? 0,
    )?.withLabel(RepresentativePlan.balanced.label);

    stopwatch.stop();

    return OptimizationResult(
      settings: settings,
      stats: OptimizationStats(
        allocationSpace: space.allocationSpace,
        candidatesGenerated: indices.length,
        candidatesPruned: space.prunedCount,
        plansEvaluated: indices.length,
        feasiblePlans: feasible.length,
        paretoPlans: frontier.length,
        runtime: stopwatch.elapsed,
        wasSampled: indices.length < space.enumerableCount,
      ),
      paretoFront: pareto.thin(
        frontier: frontier,
        limit: settings.maxParetoPlans,
      ),
      representatives: _representatives(
        feasible: scoredFeasible,
        recommended: recommended,
      ),
      bindingConstraints: _bindingConstraints(
        farm: farm,
        recommended: recommended,
        blocks: blocks,
      ),
      currentPlan: scoredCurrent?.withLabel('Current Plan'),
      recommendedPlan: recommended,
    );
  }

  /// Picks the plan that best embodies each personality.
  ///
  /// Every representative is drawn from the feasible set, so none of them can
  /// break a farmer's hard rule in the name of its own objective.
  Map<RepresentativePlan, EvaluatedPlan> _representatives({
    required List<EvaluatedPlan> feasible,
    required EvaluatedPlan? recommended,
  }) {
    final Map<RepresentativePlan, EvaluatedPlan> result =
        <RepresentativePlan, EvaluatedPlan>{};
    if (feasible.isEmpty) return result;

    if (recommended != null) {
      result[RepresentativePlan.balanced] = recommended;
    }

    _personalities.forEach((
      RepresentativePlan role,
      ObjectiveWeights personality,
    ) {
      final EvaluatedPlan? pick = _bestBy(feasible, (EvaluatedPlan plan) {
        double score = 0;
        for (final ObjectiveType type in personality.activeObjectives) {
          score += plan.normalizedObjective(type) * personality.weightOf(type);
        }
        return score;
      });
      if (pick != null) result[role] = pick.withLabel(role.label);
    });

    return result;
  }

  /// Identifies which hard constraints are actually shaping the result.
  List<BindingConstraint> _bindingConstraints({
    required Farm farm,
    required EvaluatedPlan? recommended,
    required Map<String, _BlockRecord> blocks,
  }) {
    if (recommended == null) return const <BindingConstraint>[];

    final double recommendedCash = recommended.financials.cashAfterDebtService;
    final List<BindingConstraint> binding = <BindingConstraint>[];

    for (final FarmConstraint constraint in farm.hardConstraints) {
      final double actual = _actualFor(constraint, recommended);
      final double utilisation = _utilisation(constraint, actual);
      final _BlockRecord? record = blocks[constraint.id];

      final bool blockedBetter =
          record != null && record.bestCash > recommendedCash;
      final bool atLimit = utilisation >= _bindingUtilisationThreshold;

      if (!blockedBetter && !atLimit) continue;

      binding.add(
        BindingConstraint(
          constraint: constraint,
          reason: blockedBetter
              ? BindingReason.blockedBetterPlans
              : BindingReason.atLimit,
          utilisation: utilisation,
          plansBlocked: record?.count ?? 0,
          bestBlockedProfit: blockedBetter ? record.bestCash : null,
        ),
      );
    }

    // Strongest evidence first: constraints that demonstrably cost the farm
    // money, then those merely pressed against.
    binding.sort((BindingConstraint a, BindingConstraint b) {
      if (a.reason != b.reason) {
        return a.reason == BindingReason.blockedBetterPlans ? -1 : 1;
      }
      return b.utilisation.compareTo(a.utilisation);
    });
    return List<BindingConstraint>.unmodifiable(binding);
  }

  double _actualFor(FarmConstraint constraint, EvaluatedPlan plan) {
    switch (constraint.type) {
      case ConstraintType.rotationRequired:
        return plan.violations
            .where(
              (ConstraintViolation v) =>
                  v.type == ConstraintType.rotationRequired,
            )
            .length
            .toDouble();
      case ConstraintType.restrictedInput:
        return plan.resources.acresByInputTag[constraint.textValue] ?? 0;
      default:
        return constraints.measure(
          type: constraint.type,
          financials: plan.financials,
          resources: plan.resources,
        );
    }
  }

  /// How close the plan sits to the farmer's threshold, as a fraction where
  /// 1.0 means exactly at the limit.
  double _utilisation(FarmConstraint constraint, double actual) {
    final double limit = constraint.numericValue;
    if (!actual.isFinite) return 0;
    return switch (constraint.type.direction) {
      ConstraintDirection.maximum => limit == 0 ? 0 : actual / limit,
      ConstraintDirection.minimum => actual == 0 ? 0 : limit / actual,
    };
  }

  static EvaluatedPlan? _bestBy(
    List<EvaluatedPlan> plans,
    double Function(EvaluatedPlan) score,
  ) {
    EvaluatedPlan? best;
    double bestScore = double.negativeInfinity;
    for (final EvaluatedPlan plan in plans) {
      final double value = score(plan);
      // Ties break on the allocation signature so the winner never depends on
      // iteration order.
      if (value > bestScore ||
          (value == bestScore &&
              best != null &&
              plan.signature.compareTo(best.signature) < 0)) {
        best = plan;
        bestScore = value;
      }
    }
    return best;
  }
}

/// Evidence gathered about one hard constraint during the search.
class _BlockRecord {
  _BlockRecord(this.constraint);

  final FarmConstraint constraint;

  /// Candidates this constraint rejected on its own.
  int count = 0;

  /// Best cash-after-debt-service among those candidates.
  double bestCash = double.negativeInfinity;

  _BlockRecord observe(double cash) {
    count++;
    if (cash > bestCash) bestCash = cash;
    return this;
  }
}
