import 'package:farmtwin/domain/engines/financial_engine.dart';
import 'package:farmtwin/domain/models/crop_allocation.dart';
import 'package:farmtwin/domain/models/crop_profile.dart';
import 'package:farmtwin/domain/models/farm.dart';
import 'package:farmtwin/domain/models/farm_field.dart';
import 'package:farmtwin/domain/models/field_crop_economics.dart';
import 'package:farmtwin/domain/models/plan_financials.dart';
import 'package:farmtwin/domain/models/plan_resources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_farm.dart';

void main() {
  const FinancialEngine engine = FinancialEngine();

  group('FieldCropEconomics', () {
    test(
      'revenue is yield x acres x price, adjusted by field productivity',
      () {
        final Farm farm = loadDemoFarm();
        final FarmField field = farm.field('f_west_field')!;
        final CropProfile corn = farm.crop('corn')!;

        final FieldCropEconomics cell = engine.cellFor(
          field: field,
          crop: corn,
        );

        expect(cell.yieldPerAcre, closeTo(185 * 1.04, 1e-9));
        expect(cell.revenue, closeTo(185 * 1.04 * 210 * 4.45, 1e-6));
        expect(cell.production, closeTo(185 * 1.04 * 210, 1e-9));
      },
    );

    test('dryland fields draw no water and pay no water cost', () {
      final Farm farm = loadDemoFarm();
      final FarmField dryland = farm.field('f_south_ridge')!;
      expect(dryland.irrigated, isFalse);

      final FieldCropEconomics cell = engine.cellFor(
        field: dryland,
        crop: farm.crop('soybeans')!,
      );

      expect(cell.waterAcreInches, 0);
      expect(cell.waterCost, 0);
    });

    test('irrigated fields are charged per acre-inch applied', () {
      final Farm farm = loadDemoFarm();
      final FieldCropEconomics cell = engine.cellFor(
        field: farm.field('f_west_field')!,
        crop: farm.crop('corn')!,
      );

      expect(cell.waterAcreInches, closeTo(12 * 210, 1e-9));
      expect(cell.waterCost, closeTo(12 * 210 * 9.5, 1e-6));
    });

    test('contribution margin is revenue less every variable cost', () {
      final Farm farm = loadDemoFarm();
      final FieldCropEconomics cell = engine.cellFor(
        field: farm.field('f_home_place')!,
        crop: farm.crop('winter_wheat')!,
      );

      final double costs =
          cell.seedCost +
          cell.fertilizerCost +
          cell.chemicalCost +
          cell.waterCost +
          cell.laborCost +
          cell.fuelCost +
          cell.equipmentCost;

      expect(cell.variableCost, closeTo(costs, 1e-9));
      expect(cell.contributionMargin, closeTo(cell.revenue - costs, 1e-9));
    });
  });

  group('aggregation', () {
    late Farm farm;
    late PlanFinancials financials;

    setUp(() {
      farm = loadDemoFarm();
      financials = engine.evaluateAllocation(
        farm: farm,
        allocation: farm.currentAllocation,
      );
    });

    test('planned acreage equals the farm acreage', () {
      expect(financials.totalAcres, closeTo(farm.totalAcres, 1e-9));
      expect(financials.totalAcres, closeTo(900, 1e-9));
    });

    test('acres reconcile across the per-crop breakdown', () {
      final double byCrop = financials.acresByCrop.values.fold<double>(
        0,
        (double sum, double acres) => sum + acres,
      );
      expect(byCrop, closeTo(financials.totalAcres, 1e-9));
    });

    test('revenue reconciles across the per-crop breakdown', () {
      final double byCrop = financials.revenueByCrop.values.fold<double>(
        0,
        (double sum, double revenue) => sum + revenue,
      );
      expect(byCrop, closeTo(financials.totalRevenue, 1e-6));
    });

    test('expense lines sum to the variable total', () {
      final double lines =
          financials.seedExpense +
          financials.fertilizerExpense +
          financials.chemicalExpense +
          financials.waterExpense +
          financials.laborExpense +
          financials.fuelExpense +
          financials.equipmentExpense;
      expect(financials.variableExpense, closeTo(lines, 1e-6));
    });

    test('the income chain is internally consistent', () {
      expect(
        financials.contributionMargin,
        closeTo(financials.totalRevenue - financials.variableExpense, 1e-6),
      );
      expect(
        financials.operatingIncome,
        closeTo(financials.contributionMargin - financials.fixedExpense, 1e-6),
      );
      expect(
        financials.cashAfterDebtService,
        closeTo(financials.operatingIncome - financials.debtService, 1e-6),
      );
      expect(
        financials.totalOperatingExpense,
        closeTo(financials.variableExpense + financials.fixedExpense, 1e-6),
      );
    });

    test('fixed costs and debt service come from the farm, not the plan', () {
      expect(financials.fixedExpense, closeTo(132000, 1e-9));
      expect(financials.debtService, closeTo(96000, 1e-9));
    });

    test('the demo farm currently loses money after debt service', () {
      // The demo dataset is deliberately plausible but vulnerable: it has to
      // leave the optimiser something real to find.
      expect(financials.operatingIncome, greaterThan(0));
      expect(financials.cashAfterDebtService, lessThan(0));
    });
  });

  group('break-even', () {
    test('a crop priced at its break-even covers its allocated costs', () {
      final Farm farm = loadDemoFarm();
      final PlanFinancials financials = engine.evaluateAllocation(
        farm: farm,
        allocation: farm.currentAllocation,
      );

      final double cornBreakEven = financials.breakEvenPriceByCrop['corn']!;
      final double cornAcres = financials.acresByCrop['corn']!;
      final double cornProduction = financials.productionByCrop['corn']!;
      final double cornVariable =
          financials.revenueByCrop['corn']! -
          financials.contributionMarginByCrop['corn']!;
      final double overhead =
          (financials.fixedExpense + financials.debtService) *
          (cornAcres / financials.totalAcres);

      expect(
        cornBreakEven * cornProduction,
        closeTo(cornVariable + overhead, 1e-6),
      );
    });

    test('break-even price sits above the assumed price when a crop loses '
        'money on a fully loaded basis', () {
      final Farm farm = loadDemoFarm();
      final PlanFinancials financials = engine.evaluateAllocation(
        farm: farm,
        allocation: farm.currentAllocation,
      );

      // Corn dominates the current plan and the plan does not cover its
      // obligations, so corn must be under water once overhead is charged.
      expect(
        financials.breakEvenPriceByCrop['corn'],
        greaterThan(farm.crop('corn')!.pricePerUnit),
      );
    });
  });

  group('resources', () {
    test('water and nitrogen totals match the selected cells', () {
      final Farm farm = loadDemoFarm();
      final List<FieldCropEconomics> cells = engine.cellsForAllocation(
        farm: farm,
        allocation: farm.currentAllocation,
      );
      final PlanResources resources = engine.resourcesFor(
        farm: farm,
        cells: cells,
      );

      final double water = cells.fold<double>(
        0,
        (double sum, FieldCropEconomics c) => sum + c.waterAcreInches,
      );
      final double nitrogen = cells.fold<double>(
        0,
        (double sum, FieldCropEconomics c) => sum + c.nitrogenLbs,
      );

      expect(resources.waterAcreInches, closeTo(water, 1e-9));
      expect(resources.nitrogenLbs, closeTo(nitrogen, 1e-9));
      expect(resources.waterAcreFeet, closeTo(water / 12, 1e-9));
    });

    test('diversity rises as the crop mix evens out', () {
      final Farm farm = loadDemoFarm();

      final PlanResources concentrated = engine.resourcesFor(
        farm: farm,
        cells: engine.cellsForAllocation(
          farm: farm,
          allocation: farm.currentAllocation,
        ),
      );
      final PlanResources mixed = engine.resourcesFor(
        farm: farm,
        cells: engine.cellsForAllocation(
          farm: farm,
          allocation: CropAllocation(const <String, String>{
            'f_west_field': 'corn',
            'f_north_quarter': 'soybeans',
            'f_river_bottom': 'winter_wheat',
            'f_south_ridge': 'grain_sorghum',
            'f_home_place': 'alfalfa',
            'f_east_eighty': 'winter_wheat',
          }),
        ),
      );

      expect(mixed.diversityIndex, greaterThan(concentrated.diversityIndex));
      expect(
        mixed.concentrationIndex,
        lessThan(concentrated.concentrationIndex),
      );
    });
  });

  group('validation', () {
    test('an allocation naming an unknown field is rejected', () {
      final Farm farm = loadDemoFarm();
      expect(
        () => engine.cellsForAllocation(
          farm: farm,
          allocation: CropAllocation(const <String, String>{
            'f_not_a_field': 'corn',
          }),
        ),
        throwsStateError,
      );
    });

    test('an allocation naming an unknown crop is rejected', () {
      final Farm farm = loadDemoFarm();
      expect(
        () => engine.cellsForAllocation(
          farm: farm,
          allocation: CropAllocation(const <String, String>{
            'f_west_field': 'quinoa',
          }),
        ),
        throwsStateError,
      );
    });
  });
}
