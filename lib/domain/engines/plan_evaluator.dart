import '../models/crop_allocation.dart';
import '../models/crop_profile.dart';
import '../models/evaluated_plan.dart';
import '../models/farm.dart';
import '../models/farm_constraint.dart';
import '../models/farm_field.dart';
import '../models/field_crop_economics.dart';
import '../models/plan_financials.dart';
import '../models/plan_resources.dart';
import 'constraint_engine.dart';
import 'financial_engine.dart';
import 'objective_engine.dart';

/// Runs one candidate plan through every deterministic engine.
///
/// This is the hot path of the optimiser — it executes once per candidate —
/// so it reuses a precomputed field-crop cell table rather than re-deriving
/// economics from the farm on each call.
class PlanEvaluator {
  const PlanEvaluator({
    this.financial = const FinancialEngine(),
    this.constraints = const ConstraintEngine(),
    this.objectives = const ObjectiveEngine(),
  });

  final FinancialEngine financial;
  final ConstraintEngine constraints;
  final ObjectiveEngine objectives;

  /// Evaluates [allocation] against [farm].
  ///
  /// [cellTable] is the `field → crop → economics` lookup from
  /// [FinancialEngine.buildCellTable]. Pairings missing from it — which
  /// happens when the farm's existing plan uses a combination that pruning
  /// removed — are priced on demand, so the baseline can always be shown even
  /// when it would not survive the farmer's own rules.
  EvaluatedPlan evaluate({
    required Farm farm,
    required CropAllocation allocation,
    Map<String, Map<String, FieldCropEconomics>>? cellTable,
  }) {
    final List<FieldCropEconomics> cells = _cellsFor(
      farm: farm,
      allocation: allocation,
      cellTable: cellTable,
    );

    final PlanFinancials financials = financial.aggregate(
      farm: farm,
      cells: cells,
    );
    final PlanResources resources = financial.resourcesFor(
      farm: farm,
      cells: cells,
    );
    final List<ConstraintViolation> violations = constraints.evaluate(
      farm: farm,
      allocation: allocation,
      financials: financials,
      resources: resources,
    );

    final int preferenceCount = farm.preferenceConstraints.length;

    return EvaluatedPlan(
      allocation: allocation,
      financials: financials,
      resources: resources,
      cells: List<FieldCropEconomics>.unmodifiable(cells),
      rawObjectives: objectives.rawObjectives(
        financials: financials,
        resources: resources,
        violations: violations,
        preferenceConstraintCount: preferenceCount,
      ),
      violations: List<ConstraintViolation>.unmodifiable(violations),
      preferenceConstraintCount: preferenceCount,
    );
  }

  List<FieldCropEconomics> _cellsFor({
    required Farm farm,
    required CropAllocation allocation,
    Map<String, Map<String, FieldCropEconomics>>? cellTable,
  }) {
    if (cellTable == null) {
      return financial.cellsForAllocation(farm: farm, allocation: allocation);
    }

    final List<FieldCropEconomics> cells = <FieldCropEconomics>[];
    for (final String fieldId in allocation.fieldIds) {
      final String cropId = allocation.cropFor(fieldId)!;
      final FieldCropEconomics? cached = cellTable[fieldId]?[cropId];
      if (cached != null) {
        cells.add(cached);
        continue;
      }
      final FarmField? field = farm.field(fieldId);
      final CropProfile? crop = farm.crop(cropId);
      if (field == null || crop == null) {
        throw StateError('Allocation references unknown $fieldId/$cropId.');
      }
      cells.add(financial.cellFor(field: field, crop: crop));
    }
    return cells;
  }
}
