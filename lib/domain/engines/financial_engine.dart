import 'dart:math' as math;
import '../models/farm_models.dart';
import '../models/results.dart';

/// Nominal annual cash model. Depreciation/tax/subsidies are not inferred.
class FinancialEngine {
  const FinancialEngine();
  FarmFinancialResult evaluate(
    Farm farm,
    FarmPlan plan, {
    bool validate = true,
  }) {
    if (validate) {
      farm.validate(requireReady: true);
      farm.validatePlan(plan);
    }
    final breakdown = <String, double>{
      'seed': 0,
      'fertilizer': 0,
      'chemical': 0,
      'water': 0,
      'labor': 0,
      'fuel': 0,
      'equipment': 0,
      'fixed': 0,
    };
    final rows = <FieldFinancialResult>[];
    final cropAcres = <String, double>{};
    var revenue = 0.0, variable = 0.0, water = 0.0, nitrogen = 0.0, cover = 0.0;
    final fixed = farm.expenses.fold(0.0, (sum, e) => sum + e.annualAmount);
    final debt = farm.debts.fold(0.0, (sum, d) => sum + d.paymentDue);
    for (final field in farm.fields) {
      final crop = farm.crop(plan.assignments[field.id]!);
      final yield = crop.yieldPerAcre * field.yieldMultiplier;
      final fieldRevenue = yield * crop.pricePerUnit * field.acres;
      final cost = crop.costPerAcre * field.acres;
      final fieldWater = crop.waterPerAcre * field.acres;
      final fieldNitrogen = crop.nitrogenPerAcre * field.acres;
      final allocatedFixed = fixed * (field.acres / farm.acreage);
      rows.add(
        FieldFinancialResult(
          fieldId: field.id,
          cropId: crop.id,
          acres: field.acres,
          revenue: fieldRevenue,
          cost: cost,
          waterUsage: fieldWater,
          nitrogenUsage: fieldNitrogen,
          breakEvenPrice: yield == 0
              ? null
              : (cost + allocatedFixed) / (yield * field.acres),
          breakEvenYield: crop.pricePerUnit == 0
              ? null
              : (cost + allocatedFixed) / (crop.pricePerUnit * field.acres),
        ),
      );
      revenue += fieldRevenue;
      variable += cost;
      water += fieldWater;
      nitrogen += fieldNitrogen;
      if (crop.providesSoilCover) cover += field.acres;
      cropAcres.update(
        crop.id,
        (v) => v + field.acres,
        ifAbsent: () => field.acres,
      );
      final costs = <String, double>{
        'seed': crop.seedCostPerAcre,
        'fertilizer': crop.fertilizerCostPerAcre,
        'chemical': crop.chemicalCostPerAcre,
        'water': crop.waterCostPerAcre,
        'labor': crop.laborCostPerAcre,
        'fuel': crop.fuelCostPerAcre,
        'equipment': crop.equipmentCostPerAcre,
      };
      for (final e in costs.entries) {
        breakdown[e.key] = breakdown[e.key]! + e.value * field.acres;
      }
    }
    breakdown['fixed'] = fixed;
    for (final value in [
      revenue,
      variable,
      fixed,
      debt,
      water,
      nitrogen,
      variable + fixed,
      revenue - variable - fixed - debt,
      if (debt != 0) (revenue - variable - fixed) / debt,
      for (final row in rows) ...[
        if (row.breakEvenPrice != null) row.breakEvenPrice!,
        if (row.breakEvenYield != null) row.breakEvenYield!,
      ],
      ...breakdown.values,
    ]) {
      if (!value.isFinite) {
        throw const ValidationFailure(
          'The supplied assumptions overflow the supported financial range.',
        );
      }
    }
    return FarmFinancialResult(
      revenue: revenue,
      variableExpense: variable,
      fixedExpense: fixed,
      debtService: debt,
      waterUsage: water,
      nitrogenUsage: nitrogen,
      concentration: cropAcres.isEmpty
          ? 0
          : cropAcres.values.reduce(math.max) / farm.acreage,
      diversity: cropAcres.length,
      soilCoverShare: farm.acreage == 0 ? 0 : cover / farm.acreage,
      acreage: farm.acreage,
      costBreakdown: breakdown,
      fields: rows,
    );
  }
}
