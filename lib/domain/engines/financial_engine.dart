import '../models/crop_allocation.dart';
import '../models/crop_profile.dart';
import '../models/debt.dart';
import '../models/farm.dart';
import '../models/farm_field.dart';
import '../models/field_crop_economics.dart';
import '../models/plan_financials.dart';
import '../models/plan_resources.dart';

/// Deterministic farm accounting.
///
/// The engine is split into two steps on purpose. [cellFor] prices a single
/// field-crop pairing, and there are only `fields × crops` of those; [aggregate]
/// then rolls up whichever cells a candidate plan selected. Precomputing the
/// cells once turns scoring thousands of plans into thousands of additions.
///
/// Nothing here is estimated or inferred. Every output traces back to a
/// farmer-supplied assumption on the farm's twin.
class FinancialEngine {
  const FinancialEngine();

  /// Prices one crop on one field.
  ///
  /// Yield is the crop's baseline scaled by the field's productivity
  /// multiplier. Irrigation is charged only where the field can actually
  /// deliver it — a dryland field draws no water and pays no water cost,
  /// carrying its lower yield instead.
  FieldCropEconomics cellFor({
    required FarmField field,
    required CropProfile crop,
  }) {
    final double acres = field.acres;
    final double yieldPerAcre =
        crop.expectedYieldPerAcre * field.yieldMultiplier;
    final bool irrigated = field.irrigated;

    final double waterAcreInches = irrigated
        ? crop.waterAcreInchesPerAcre * acres
        : 0;

    return FieldCropEconomics(
      fieldId: field.id,
      cropId: crop.id,
      acres: acres,
      yieldPerAcre: yieldPerAcre,
      pricePerUnit: crop.pricePerUnit,
      revenue: yieldPerAcre * acres * crop.pricePerUnit,
      seedCost: crop.seedCostPerAcre * acres,
      fertilizerCost: crop.fertilizerCostPerAcre * acres,
      chemicalCost: crop.chemicalCostPerAcre * acres,
      waterCost: waterAcreInches * crop.waterCostPerAcreInch,
      laborCost: crop.laborCostPerAcre * acres,
      fuelCost: crop.fuelCostPerAcre * acres,
      equipmentCost: crop.equipmentCostPerAcre * acres,
      waterAcreInches: waterAcreInches,
      nitrogenLbs: crop.nitrogenLbsPerAcre * acres,
      irrigated: irrigated,
    );
  }

  /// Builds the complete `field → crop → economics` table for a farm.
  ///
  /// Only agronomically permitted pairings are included; [allowedCropIds]
  /// comes from the candidate generator's pruning pass.
  Map<String, Map<String, FieldCropEconomics>> buildCellTable({
    required Farm farm,
    Map<String, List<String>>? allowedCropIds,
  }) {
    final Map<String, Map<String, FieldCropEconomics>> table =
        <String, Map<String, FieldCropEconomics>>{};
    for (final FarmField field in farm.fields) {
      final List<String> cropIds =
          allowedCropIds?[field.id] ??
          farm.cropProfiles.map((CropProfile c) => c.id).toList();
      final Map<String, FieldCropEconomics> row =
          <String, FieldCropEconomics>{};
      for (final String cropId in cropIds) {
        final CropProfile? crop = farm.crop(cropId);
        if (crop == null) continue;
        row[cropId] = cellFor(field: field, crop: crop);
      }
      table[field.id] = row;
    }
    return table;
  }

  /// Resolves an allocation into the cells it selects.
  ///
  /// Throws [StateError] when the allocation references a field or crop the
  /// farm does not define, so a malformed plan fails loudly instead of
  /// silently costing fewer acres than the farm actually has.
  List<FieldCropEconomics> cellsForAllocation({
    required Farm farm,
    required CropAllocation allocation,
  }) {
    final List<FieldCropEconomics> cells = <FieldCropEconomics>[];
    for (final String fieldId in allocation.fieldIds) {
      final FarmField? field = farm.field(fieldId);
      if (field == null) {
        throw StateError('Allocation references unknown field "$fieldId".');
      }
      final String cropId = allocation.cropFor(fieldId)!;
      final CropProfile? crop = farm.crop(cropId);
      if (crop == null) {
        throw StateError('Allocation references unknown crop "$cropId".');
      }
      cells.add(cellFor(field: field, crop: crop));
    }
    return cells;
  }

  /// Rolls selected cells up into a full financial picture.
  PlanFinancials aggregate({
    required Farm farm,
    required List<FieldCropEconomics> cells,
  }) {
    double totalAcres = 0;
    double totalRevenue = 0;
    double seed = 0;
    double fertilizer = 0;
    double chemical = 0;
    double water = 0;
    double labor = 0;
    double fuel = 0;
    double equipment = 0;

    final Map<String, double> acresByCrop = <String, double>{};
    final Map<String, double> revenueByCrop = <String, double>{};
    final Map<String, double> variableByCrop = <String, double>{};
    final Map<String, double> productionByCrop = <String, double>{};

    for (final FieldCropEconomics cell in cells) {
      totalAcres += cell.acres;
      totalRevenue += cell.revenue;
      seed += cell.seedCost;
      fertilizer += cell.fertilizerCost;
      chemical += cell.chemicalCost;
      water += cell.waterCost;
      labor += cell.laborCost;
      fuel += cell.fuelCost;
      equipment += cell.equipmentCost;

      acresByCrop.update(
        cell.cropId,
        (double v) => v + cell.acres,
        ifAbsent: () => cell.acres,
      );
      revenueByCrop.update(
        cell.cropId,
        (double v) => v + cell.revenue,
        ifAbsent: () => cell.revenue,
      );
      variableByCrop.update(
        cell.cropId,
        (double v) => v + cell.variableCost,
        ifAbsent: () => cell.variableCost,
      );
      productionByCrop.update(
        cell.cropId,
        (double v) => v + cell.production,
        ifAbsent: () => cell.production,
      );
    }

    final double fixedExpense = farm.totalFixedExpense;
    final double debtService = farm.totalDebtService;
    final double debtInterest = farm.debts.fold<double>(
      0,
      (double sum, Debt d) => sum + d.annualInterest,
    );

    final Map<String, double> contributionByCrop = <String, double>{
      for (final String cropId in _sortedKeys(acresByCrop))
        cropId: (revenueByCrop[cropId] ?? 0) - (variableByCrop[cropId] ?? 0),
    };

    // Break-even needs overhead attributed to each crop. FarmTwin allocates
    // fixed cost and debt service by acreage share, which is the convention
    // farm financial statements use and, unlike a margin-weighted split,
    // never flatters a crop for being profitable.
    final Map<String, double> breakEvenPrice = <String, double>{};
    final Map<String, double> breakEvenYield = <String, double>{};
    for (final String cropId in _sortedKeys(acresByCrop)) {
      final double acres = acresByCrop[cropId] ?? 0;
      if (acres <= 0) continue;
      final double overhead = totalAcres > 0
          ? (fixedExpense + debtService) * (acres / totalAcres)
          : 0;
      final double costToCover = (variableByCrop[cropId] ?? 0) + overhead;

      final double production = productionByCrop[cropId] ?? 0;
      if (production > 0) {
        breakEvenPrice[cropId] = costToCover / production;
      }
      final double price = farm.crop(cropId)?.pricePerUnit ?? 0;
      if (price > 0) {
        breakEvenYield[cropId] = costToCover / (price * acres);
      }
    }

    return PlanFinancials(
      totalAcres: totalAcres,
      totalRevenue: totalRevenue,
      seedExpense: seed,
      fertilizerExpense: fertilizer,
      chemicalExpense: chemical,
      waterExpense: water,
      laborExpense: labor,
      fuelExpense: fuel,
      equipmentExpense: equipment,
      fixedExpense: fixedExpense,
      debtService: debtService,
      debtInterest: debtInterest,
      acresByCrop: _sorted(acresByCrop),
      revenueByCrop: _sorted(revenueByCrop),
      contributionMarginByCrop: _sorted(contributionByCrop),
      productionByCrop: _sorted(productionByCrop),
      breakEvenPriceByCrop: _sorted(breakEvenPrice),
      breakEvenYieldByCrop: _sorted(breakEvenYield),
    );
  }

  /// Totals the physical resources the selected cells consume.
  PlanResources resourcesFor({
    required Farm farm,
    required List<FieldCropEconomics> cells,
  }) {
    double totalAcres = 0;
    double water = 0;
    double nitrogen = 0;
    double soilCoverAcres = 0;
    double irrigatedAcresPlanted = 0;
    final Map<String, double> acresByCrop = <String, double>{};
    final Map<String, double> acresByTag = <String, double>{};

    for (final FieldCropEconomics cell in cells) {
      totalAcres += cell.acres;
      water += cell.waterAcreInches;
      nitrogen += cell.nitrogenLbs;
      if (cell.irrigated) irrigatedAcresPlanted += cell.acres;

      final CropProfile? crop = farm.crop(cell.cropId);
      if (crop != null) {
        if (crop.providesSoilCover) soilCoverAcres += cell.acres;
        for (final String tag in crop.inputTags) {
          acresByTag.update(
            tag,
            (double v) => v + cell.acres,
            ifAbsent: () => cell.acres,
          );
        }
      }
      acresByCrop.update(
        cell.cropId,
        (double v) => v + cell.acres,
        ifAbsent: () => cell.acres,
      );
    }

    return PlanResources(
      totalAcres: totalAcres,
      waterAcreInches: water,
      nitrogenLbs: nitrogen,
      soilCoverAcres: soilCoverAcres,
      irrigatedAcresPlanted: irrigatedAcresPlanted,
      acresByCrop: _sorted(acresByCrop),
      acresByInputTag: _sorted(acresByTag),
    );
  }

  /// Convenience path for a single plan, used by tests and detail screens.
  PlanFinancials evaluateAllocation({
    required Farm farm,
    required CropAllocation allocation,
  }) => aggregate(
    farm: farm,
    cells: cellsForAllocation(farm: farm, allocation: allocation),
  );

  static List<String> _sortedKeys(Map<String, double> source) =>
      source.keys.toList()..sort();

  /// Rebuilds a map in sorted key order so that results serialise and render
  /// identically across runs.
  static Map<String, double> _sorted(Map<String, double> source) =>
      Map<String, double>.unmodifiable(<String, double>{
        for (final String key in _sortedKeys(source)) key: source[key]!,
      });
}
