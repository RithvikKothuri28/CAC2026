import 'crop_allocation.dart';
import 'farm_constraint.dart';
import 'field_crop_economics.dart';
import 'objective.dart';
import 'plan_financials.dart';
import 'plan_resources.dart';

/// A candidate farm plan with every deterministic result attached.
///
/// Raw objective values are computed per plan. Normalised values and the
/// weighted score can only be assigned once the whole candidate set is known,
/// so the optimiser attaches them later via [withScores].
class EvaluatedPlan {
  const EvaluatedPlan({
    required this.allocation,
    required this.financials,
    required this.resources,
    required this.cells,
    required this.rawObjectives,
    required this.violations,
    required this.preferenceConstraintCount,
    this.normalizedObjectives,
    this.weightedScore,
    this.label = '',
  });

  final CropAllocation allocation;
  final PlanFinancials financials;
  final PlanResources resources;

  /// The per-field economics this plan selected. Retained so the Monte Carlo
  /// engine can re-price the same plan under shocked assumptions without
  /// re-deriving it from the farm.
  final List<FieldCropEconomics> cells;

  /// Objective values in their natural units, always "higher is better".
  final Map<ObjectiveType, double> rawObjectives;

  /// Constraints this plan failed, hard and preference alike.
  final List<ConstraintViolation> violations;

  /// How many preference constraints were evaluated, the denominator behind
  /// the "7 / 7 requirements satisfied" readout.
  final int preferenceConstraintCount;

  /// Objective values rescaled to 0..1 across the evaluated candidate set.
  final Map<ObjectiveType, double>? normalizedObjectives;

  /// Weighted sum of [normalizedObjectives], 0..1.
  final double? weightedScore;

  /// Presentation name, e.g. `Balanced` or `Resource Efficient`.
  final String label;

  /// A plan is feasible when it breaks no hard constraint. Preference
  /// violations never remove a plan from the feasible set.
  bool get isFeasible => !violations.any((ConstraintViolation v) => v.isHard);

  List<ConstraintViolation> get hardViolations => violations
      .where((ConstraintViolation v) => v.isHard)
      .toList(growable: false);

  List<ConstraintViolation> get preferenceViolations => violations
      .where((ConstraintViolation v) => !v.isHard)
      .toList(growable: false);

  /// Preference constraints satisfied, the numerator of practice alignment.
  int get satisfiedPreferenceCount =>
      preferenceConstraintCount - preferenceViolations.length;

  /// Stable identifier for this allocation.
  String get signature => allocation.signature;

  double rawObjective(ObjectiveType type) => rawObjectives[type] ?? 0;

  double normalizedObjective(ObjectiveType type) =>
      normalizedObjectives?[type] ?? 0;

  /// The fields whose crop differs from [other] — the "what changed" list.
  List<String> changedFieldsVersus(EvaluatedPlan other) {
    final List<String> changed = <String>[];
    for (final String fieldId in allocation.fieldIds) {
      if (allocation.cropFor(fieldId) != other.allocation.cropFor(fieldId)) {
        changed.add(fieldId);
      }
    }
    return changed;
  }

  EvaluatedPlan withScores({
    required Map<ObjectiveType, double> normalized,
    required double score,
  }) => EvaluatedPlan(
    allocation: allocation,
    financials: financials,
    resources: resources,
    cells: cells,
    rawObjectives: rawObjectives,
    violations: violations,
    preferenceConstraintCount: preferenceConstraintCount,
    normalizedObjectives: Map<ObjectiveType, double>.unmodifiable(normalized),
    weightedScore: score,
    label: label,
  );

  EvaluatedPlan withLabel(String newLabel) => EvaluatedPlan(
    allocation: allocation,
    financials: financials,
    resources: resources,
    cells: cells,
    rawObjectives: rawObjectives,
    violations: violations,
    preferenceConstraintCount: preferenceConstraintCount,
    normalizedObjectives: normalizedObjectives,
    weightedScore: weightedScore,
    label: newLabel,
  );

  @override
  String toString() =>
      'EvaluatedPlan(${label.isEmpty ? signature : label}, '
      'feasible=$isFeasible, '
      'cash=${financials.cashAfterDebtService.toStringAsFixed(0)})';
}
