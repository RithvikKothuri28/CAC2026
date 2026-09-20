import '../models/farm_models.dart';
import '../models/results.dart';

class ConstraintEngine {
  const ConstraintEngine();

  /// Most recent history entry is first. Historical crop ids must be retained
  /// in the crop catalogue to evaluate botanical-family rotation correctly.
  bool rotationAllowed(Farm farm, Field field, CropProfile crop) {
    for (final id in field.cropHistory.take(crop.minimumRotationYears)) {
      final historical = farm.crops.where((c) => c.id == id).firstOrNull;
      if (historical == null) {
        throw DataUnavailableFailure(
          'Historical crop $id needs a crop profile before rotation can be evaluated.',
        );
      }
      if (historical.rotationFamily == crop.rotationFamily) return false;
    }
    return true;
  }

  ConstraintReport evaluate(
    Farm farm,
    FarmPlan plan,
    FarmFinancialResult financial,
  ) {
    final checks = <ConstraintCheck>[];
    for (final rule in farm.constraints.where(
      (r) => r.mode != ConstraintMode.disabled,
    )) {
      rule.validate();
      double actual;
      var maximum = true;
      var threshold = rule.limit;
      switch (rule.kind) {
        case ConstraintKind.maxWater:
          actual = financial.waterUsage;
        case ConstraintKind.maxNitrogen:
          actual = financial.nitrogenUsage;
        case ConstraintKind.maxOperatingExpense:
          actual = financial.operatingExpense;
        case ConstraintKind.minOperatingIncome:
          actual = financial.operatingIncome;
          maximum = false;
        case ConstraintKind.maxConcentration:
          actual = financial.concentration;
        case ConstraintKind.minDiversity:
          actual = financial.diversity.toDouble();
          maximum = false;
        case ConstraintKind.minLiquidity:
          actual = financial.cashAfterDebt + farm.settings.liquidityReserve;
          maximum = false;
        case ConstraintKind.minDebtCoverage:
          // With no payment due the coverage requirement is satisfied; encode
          // the threshold rather than Infinity to keep persisted JSON finite.
          actual = financial.debtCoverage ?? rule.limit;
          maximum = false;
        case ConstraintKind.minSoilCover:
          actual = financial.soilCoverShare;
          maximum = false;
        case ConstraintKind.maxDebt:
          actual = farm.debts.fold(0.0, (a, d) => a + d.balance);
        case ConstraintKind.rotation:
          threshold = 0;
          actual = farm.fields
              .where(
                (f) => !rotationAllowed(
                  farm,
                  f,
                  farm.crop(plan.assignments[f.id]!),
                ),
              )
              .length
              .toDouble();
        case ConstraintKind.restrictedInputs:
          threshold = 0;
          actual = plan.assignments.values
              .map(farm.crop)
              .where((c) => c.inputs.any(rule.restrictedInputs.contains))
              .length
              .toDouble();
      }
      final satisfied = maximum
          ? actual <= threshold + numericTolerance
          : actual + numericTolerance >= threshold;
      checks.add(
        ConstraintCheck(
          constraintId: rule.id,
          name: rule.name,
          kind: rule.kind,
          mode: rule.mode,
          actual: actual,
          limit: threshold,
          satisfied: satisfied,
          utilization: maximum && threshold > 0 ? actual / threshold : null,
        ),
      );
    }
    return ConstraintReport(checks);
  }
}
