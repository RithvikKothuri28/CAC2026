import '../models/crop_allocation.dart';
import '../models/crop_profile.dart';
import '../models/farm.dart';
import '../models/farm_constraint.dart';
import '../models/farm_field.dart';
import '../models/plan_financials.dart';
import '../models/plan_resources.dart';

/// A field whose assigned crop breaks a rotation rule.
class RotationConflict {
  const RotationConflict({
    required this.fieldId,
    required this.cropId,
    required this.reason,
  });

  final String fieldId;
  final String cropId;
  final String reason;

  @override
  String toString() => 'RotationConflict($fieldId: $reason)';
}

/// Checks farm plans against the farmer's own operating rules.
///
/// The engine measures; it does not decide. Whether a violation removes a
/// plan from the feasible set is determined entirely by the farmer's
/// [ConstraintMode] on that constraint.
class ConstraintEngine {
  const ConstraintEngine();

  /// Evaluates every active constraint against one plan.
  ///
  /// Returns only the violations. Hard and preference violations are both
  /// reported; callers distinguish them via [ConstraintViolation.isHard].
  List<ConstraintViolation> evaluate({
    required Farm farm,
    required CropAllocation allocation,
    required PlanFinancials financials,
    required PlanResources resources,
  }) {
    final List<ConstraintViolation> violations = <ConstraintViolation>[];

    for (final FarmConstraint constraint in farm.activeConstraints) {
      switch (constraint.type) {
        case ConstraintType.rotationRequired:
          final List<RotationConflict> conflicts = rotationConflicts(
            farm: farm,
            allocation: allocation,
          );
          final double actual = conflicts.length.toDouble();
          if (!constraint.isSatisfiedBy(actual)) {
            violations.add(
              ConstraintViolation(
                constraint: constraint,
                actual: actual,
                detail: conflicts
                    .map((RotationConflict c) => c.reason)
                    .join('; '),
              ),
            );
          }

        case ConstraintType.restrictedInput:
          final double acres =
              resources.acresByInputTag[constraint.textValue] ?? 0;
          if (!constraint.isSatisfiedBy(acres)) {
            violations.add(
              ConstraintViolation(
                constraint: constraint,
                actual: acres,
                detail:
                    '${acres.toStringAsFixed(0)} acres use '
                    '"${constraint.textValue}"',
              ),
            );
          }

        default:
          final double actual = measure(
            type: constraint.type,
            financials: financials,
            resources: resources,
          );
          if (!constraint.isSatisfiedBy(actual)) {
            violations.add(
              ConstraintViolation(constraint: constraint, actual: actual),
            );
          }
      }
    }

    return violations;
  }

  /// The plan's measured value for [type], in the constraint's own unit.
  ///
  /// Rotation and restricted-input are excluded because they are measured
  /// from the allocation rather than from the rolled-up totals; [evaluate]
  /// handles those directly.
  double measure({
    required ConstraintType type,
    required PlanFinancials financials,
    required PlanResources resources,
  }) => switch (type) {
    ConstraintType.maxWaterAcreInches => resources.waterAcreInches,
    ConstraintType.maxNitrogenLbs => resources.nitrogenLbs,
    ConstraintType.maxOperatingExpense => financials.totalOperatingExpense,
    ConstraintType.minOperatingIncome => financials.operatingIncome,
    ConstraintType.minCashAfterDebtService => financials.cashAfterDebtService,
    ConstraintType.minDebtServiceCoverage =>
      financials.debtServiceCoverageRatio,
    ConstraintType.maxCropConcentration => financials.maxCropConcentration,
    ConstraintType.minCropCount => financials.cropCount.toDouble(),
    ConstraintType.minSoilCoverShare => resources.soilCoverShare,
    ConstraintType.rotationRequired => 0,
    ConstraintType.restrictedInput => 0,
  };

  /// Fields whose assigned crop breaks a rotation rule.
  List<RotationConflict> rotationConflicts({
    required Farm farm,
    required CropAllocation allocation,
  }) {
    final List<RotationConflict> conflicts = <RotationConflict>[];
    for (final String fieldId in allocation.fieldIds) {
      final FarmField? field = farm.field(fieldId);
      final String? cropId = allocation.cropFor(fieldId);
      if (field == null || cropId == null) continue;
      final CropProfile? crop = farm.crop(cropId);
      if (crop == null) continue;

      final String? reason = rotationReason(
        field: field,
        crop: crop,
        planYear: farm.planYear,
      );
      if (reason != null) {
        conflicts.add(
          RotationConflict(fieldId: fieldId, cropId: cropId, reason: reason),
        );
      }
    }
    return conflicts;
  }

  /// Why [crop] may not be planted on [field] this season, or null if it may.
  ///
  /// Two rules apply: a crop may not directly follow one listed in its
  /// `cannotFollow` set, and it must observe its own rest period. A field
  /// with no recorded history is treated as unconstrained rather than
  /// assumed clean or assumed dirty — FarmTwin does not invent history.
  String? rotationReason({
    required FarmField field,
    required CropProfile crop,
    required int planYear,
  }) {
    final String? previous = field.cropInYear(planYear - 1);
    if (previous != null && crop.cannotFollow.contains(previous)) {
      return '${field.name}: ${crop.name} cannot follow $previous';
    }

    if (crop.minYearsBetweenPlantings > 0) {
      final int? gap = field.seasonsSince(crop.id, planYear);
      if (gap != null && gap < crop.minYearsBetweenPlantings) {
        return '${field.name}: ${crop.name} needs '
            '${crop.minYearsBetweenPlantings} seasons between plantings, '
            'last grown $gap season${gap == 1 ? '' : 's'} ago';
      }
    }

    return null;
  }

  /// Whether [crop] can be assigned to [field] at all.
  ///
  /// This is the pruning test the candidate generator applies before
  /// enumeration. It covers only rules that depend on the single field-crop
  /// pairing; farm-wide rules such as water totals can only be judged once a
  /// whole plan exists.
  bool isPairingAllowed({
    required Farm farm,
    required FarmField field,
    required CropProfile crop,
    required bool enforceRotation,
    Set<String> restrictedTags = const <String>{},
  }) {
    if (crop.requiresIrrigation && !field.irrigated) return false;

    if (crop.compatibleSoilTypes.isNotEmpty &&
        !crop.compatibleSoilTypes.contains(field.soilType)) {
      return false;
    }

    if (restrictedTags.isNotEmpty &&
        crop.inputTags.any(restrictedTags.contains)) {
      return false;
    }

    if (enforceRotation &&
        rotationReason(field: field, crop: crop, planYear: farm.planYear) !=
            null) {
      return false;
    }

    return true;
  }

  /// Input tags banned outright by a hard `restrictedInput` constraint whose
  /// threshold is zero acres. Anything above zero is a farm-wide limit and
  /// cannot be pruned per field.
  Set<String> hardRestrictedTags(Farm farm) => <String>{
    for (final FarmConstraint c in farm.constraints)
      if (c.isHard &&
          c.type == ConstraintType.restrictedInput &&
          c.numericValue <= 0 &&
          c.textValue.isNotEmpty)
        c.textValue,
  };

  /// Whether rotation rules are hard for this farm, and therefore safe to
  /// prune on before enumeration.
  bool rotationIsHard(Farm farm) => farm.constraints.any(
    (FarmConstraint c) =>
        c.isHard &&
        c.type == ConstraintType.rotationRequired &&
        c.numericValue <= 0,
  );
}
