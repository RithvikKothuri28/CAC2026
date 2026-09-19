import '../models/evaluated_plan.dart';
import '../models/objective.dart';

/// Extracts the set of efficient farm plans.
///
/// A plan is *dominated* when another plan is at least as good on every
/// objective and strictly better on at least one. Dominated plans are never
/// worth showing a farmer: something else beats them outright. What remains is
/// the Pareto frontier, where every plan is a genuine tradeoff rather than a
/// mistake.
class ParetoEngine {
  const ParetoEngine();

  /// Objective values closer than this are treated as equal, so floating
  /// point noise cannot manufacture a false tradeoff.
  static const double _epsilon = 1e-9;

  /// Returns the non-dominated plans from [plans], comparing on [objectives].
  ///
  /// The comparison uses normalised objective values when scoring has already
  /// run, and raw values otherwise — both are monotonic in the same
  /// direction, so the frontier is identical either way.
  ///
  /// Implementation is incremental archive filtering: each plan is checked
  /// against the current frontier, which it either joins (evicting anything
  /// it dominates) or is discarded by. That costs `O(n × frontier)` rather
  /// than the `O(n²)` of comparing every pair, which matters because the
  /// frontier is typically a tiny fraction of the candidate set.
  List<EvaluatedPlan> frontier({
    required List<EvaluatedPlan> plans,
    required List<ObjectiveType> objectives,
  }) {
    if (plans.isEmpty || objectives.isEmpty) return const <EvaluatedPlan>[];

    // Sorting by the first objective lets strong plans enter the archive
    // early, so weak plans are rejected after fewer comparisons.
    final List<EvaluatedPlan> ordered = List<EvaluatedPlan>.of(plans)
      ..sort((EvaluatedPlan a, EvaluatedPlan b) {
        final int byObjective = _value(
          b,
          objectives.first,
        ).compareTo(_value(a, objectives.first));
        if (byObjective != 0) return byObjective;
        // Deterministic tiebreak so identical inputs always yield the same
        // frontier ordering.
        return a.signature.compareTo(b.signature);
      });

    final List<EvaluatedPlan> archive = <EvaluatedPlan>[];

    for (final EvaluatedPlan candidate in ordered) {
      bool dominated = false;
      for (final EvaluatedPlan incumbent in archive) {
        if (dominates(incumbent, candidate, objectives)) {
          dominated = true;
          break;
        }
      }
      if (dominated) continue;

      archive.removeWhere(
        (EvaluatedPlan incumbent) =>
            dominates(candidate, incumbent, objectives),
      );
      archive.add(candidate);
    }

    archive.sort(
      (EvaluatedPlan a, EvaluatedPlan b) => b.financials.cashAfterDebtService
          .compareTo(a.financials.cashAfterDebtService),
    );
    return List<EvaluatedPlan>.unmodifiable(archive);
  }

  /// True when [a] dominates [b].
  bool dominates(
    EvaluatedPlan a,
    EvaluatedPlan b,
    List<ObjectiveType> objectives,
  ) {
    bool strictlyBetterSomewhere = false;
    for (final ObjectiveType objective in objectives) {
      final double aValue = _value(a, objective);
      final double bValue = _value(b, objective);
      if (aValue < bValue - _epsilon) return false;
      if (aValue > bValue + _epsilon) strictlyBetterSomewhere = true;
    }
    return strictlyBetterSomewhere;
  }

  /// Reduces a large frontier to at most [limit] plans for display.
  ///
  /// The frontier is thinned by even spacing rather than truncated, so the
  /// extremes — the highest-profit and lowest-resource plans — always survive.
  /// Truncating would quietly delete exactly the tradeoffs worth seeing.
  List<EvaluatedPlan> thin({
    required List<EvaluatedPlan> frontier,
    required int limit,
  }) {
    if (limit <= 0 || frontier.length <= limit) return frontier;
    if (limit == 1) return <EvaluatedPlan>[frontier.first];

    final List<EvaluatedPlan> kept = <EvaluatedPlan>[];
    final double step = (frontier.length - 1) / (limit - 1);
    for (int i = 0; i < limit; i++) {
      kept.add(frontier[(i * step).round()]);
    }
    return List<EvaluatedPlan>.unmodifiable(kept);
  }

  static double _value(EvaluatedPlan plan, ObjectiveType objective) =>
      plan.normalizedObjectives != null
      ? plan.normalizedObjective(objective)
      : plan.rawObjective(objective);
}
