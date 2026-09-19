import '../models/evaluated_plan.dart';
import '../models/farm_constraint.dart';
import '../models/objective.dart';
import '../models/plan_financials.dart';
import '../models/plan_resources.dart';

/// Turns a plan's financial and resource results into comparable objective
/// scores.
///
/// Two stages, and the split matters. [rawObjectives] is per plan and uses
/// real units — dollars, acre-inches, ratios. [normalize] rescales those
/// across the whole candidate set, because "is $46,000 of cash good?" is only
/// answerable relative to what else the farm could have done.
class ObjectiveEngine {
  const ObjectiveEngine();

  /// Weighting inside the composite resilience score.
  ///
  /// Margin cushion is how far revenue can fall before operations stop
  /// covering their own costs; coverage is how comfortably the bank gets
  /// paid. Cushion carries slightly more weight because a farm can
  /// renegotiate debt more easily than it can conjure margin.
  static const double _cushionWeight = 0.55;
  static const double _coverageWeight = 0.45;

  /// Coverage above this is treated as equally safe, so a debt-free plan does
  /// not score arbitrarily high and swamp the other objectives.
  static const double _coverageCap = 3.0;

  /// Objective values in natural units, always oriented so larger is better.
  Map<ObjectiveType, double> rawObjectives({
    required PlanFinancials financials,
    required PlanResources resources,
    required List<ConstraintViolation> violations,
    required int preferenceConstraintCount,
  }) {
    final int preferenceViolations = violations
        .where((ConstraintViolation v) => !v.isHard)
        .length;

    return <ObjectiveType, double>{
      ObjectiveType.expectedProfit: financials.cashAfterDebtService,
      ObjectiveType.financialResilience: _resilience(financials),
      // Negated: a plan that draws less water scores higher.
      ObjectiveType.waterEfficiency: -resources.waterAcreInches,
      ObjectiveType.inputEfficiency: -_purchasedInputIntensity(financials),
      ObjectiveType.practiceAlignment: _alignment(
        preferenceConstraintCount,
        preferenceViolations,
      ),
      ObjectiveType.diversification: resources.diversityIndex,
    };
  }

  /// Deterministic resilience proxy, computed without simulation so it can
  /// score thousands of candidates. The Monte Carlo engine later measures
  /// the real distribution for the handful of plans the farmer shortlists.
  double _resilience(PlanFinancials financials) {
    final double cushion = financials.contributionMarginRatio;
    final double coverage =
        financials.clampedCoverage(cap: _coverageCap) / _coverageCap;
    return (_cushionWeight * cushion) + (_coverageWeight * coverage);
  }

  /// Fertiliser and chemical spend per acre — the purchased inputs that carry
  /// both cost and environmental exposure. Seed is excluded because it is
  /// effectively fixed per crop choice rather than a rate decision.
  double _purchasedInputIntensity(PlanFinancials financials) {
    if (financials.totalAcres <= 0) return 0;
    return (financials.fertilizerExpense + financials.chemicalExpense) /
        financials.totalAcres;
  }

  /// Share of the farmer's preference constraints the plan satisfies. A farm
  /// with no preferences set is fully aligned by definition.
  double _alignment(int total, int violated) {
    if (total <= 0) return 1;
    final int satisfied = total - violated;
    return (satisfied / total).clamp(0.0, 1.0).toDouble();
  }

  /// Rescales every objective to 0..1 across [plans] and attaches the
  /// weighted score.
  ///
  /// Min-max is used rather than z-scores because the frontier's extremes are
  /// exactly what the tradeoff explorer needs to show, and min-max keeps them
  /// pinned at 0 and 1. When every plan shares a value the objective cannot
  /// discriminate, so all plans receive 1.0 and it drops out of the ranking.
  List<EvaluatedPlan> normalize({
    required List<EvaluatedPlan> plans,
    required ObjectiveWeights weights,
  }) {
    if (plans.isEmpty) return plans;

    final Map<ObjectiveType, double> minima = <ObjectiveType, double>{};
    final Map<ObjectiveType, double> maxima = <ObjectiveType, double>{};

    for (final ObjectiveType type in ObjectiveType.values) {
      double min = double.infinity;
      double max = double.negativeInfinity;
      for (final EvaluatedPlan plan in plans) {
        final double value = plan.rawObjective(type);
        if (!value.isFinite) continue;
        if (value < min) min = value;
        if (value > max) max = value;
      }
      minima[type] = min;
      maxima[type] = max;
    }

    return plans
        .map((EvaluatedPlan plan) {
          final Map<ObjectiveType, double> normalized =
              <ObjectiveType, double>{};
          double score = 0;

          for (final ObjectiveType type in ObjectiveType.values) {
            final double min = minima[type] ?? 0;
            final double max = maxima[type] ?? 0;
            final double raw = plan.rawObjective(type);

            final double unit;
            if (!min.isFinite || !max.isFinite || (max - min).abs() < 1e-12) {
              unit = 1;
            } else {
              unit = ((raw - min) / (max - min)).clamp(0.0, 1.0).toDouble();
            }

            normalized[type] = unit;
            score += unit * weights.weightOf(type);
          }

          return plan.withScores(normalized: normalized, score: score);
        })
        .toList(growable: false);
  }
}
