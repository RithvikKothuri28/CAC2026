import 'package:farmtwin/domain/engines/constraint_engine.dart';
import 'package:farmtwin/domain/engines/financial_engine.dart';
import 'package:farmtwin/domain/models/crop_allocation.dart';
import 'package:farmtwin/domain/models/crop_profile.dart';
import 'package:farmtwin/domain/models/farm.dart';
import 'package:farmtwin/domain/models/farm_constraint.dart';
import 'package:farmtwin/domain/models/farm_field.dart';
import 'package:farmtwin/domain/models/field_crop_economics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_farm.dart';

void main() {
  const ConstraintEngine constraints = ConstraintEngine();
  const FinancialEngine financial = FinancialEngine();

  List<ConstraintViolation> evaluate(Farm farm, CropAllocation allocation) {
    final List<FieldCropEconomics> cells = financial.cellsForAllocation(
      farm: farm,
      allocation: allocation,
    );
    return constraints.evaluate(
      farm: farm,
      allocation: allocation,
      financials: financial.aggregate(farm: farm, cells: cells),
      resources: financial.resourcesFor(farm: farm, cells: cells),
    );
  }

  group('satisfaction', () {
    test('a maximum constraint accepts a value exactly on the limit', () {
      const FarmConstraint limit = FarmConstraint(
        id: 'c',
        type: ConstraintType.maxWaterAcreInches,
        mode: ConstraintMode.hard,
        numericValue: 7800,
      );
      expect(limit.isSatisfiedBy(7800), isTrue);
      expect(limit.isSatisfiedBy(7799.99), isTrue);
      expect(limit.isSatisfiedBy(7800.01), isFalse);
    });

    test('a minimum constraint accepts a value exactly on the limit', () {
      const FarmConstraint floor = FarmConstraint(
        id: 'c',
        type: ConstraintType.minCropCount,
        mode: ConstraintMode.hard,
        numericValue: 3,
      );
      expect(floor.isSatisfiedBy(3), isTrue);
      expect(floor.isSatisfiedBy(4), isTrue);
      expect(floor.isSatisfiedBy(2), isFalse);
    });

    test('floating point drift at the limit does not fail a plan', () {
      const FarmConstraint limit = FarmConstraint(
        id: 'c',
        type: ConstraintType.maxCropConcentration,
        mode: ConstraintMode.hard,
        numericValue: 0.5,
      );
      // 0.1 + 0.4 is famously not exactly 0.5 in binary floating point.
      expect(limit.isSatisfiedBy(0.1 + 0.4), isTrue);
    });
  });

  group('rotation', () {
    test('a crop may not directly follow itself', () {
      final Farm farm = loadDemoFarm();
      final FarmField northQuarter = farm.field('f_north_quarter')!;
      expect(northQuarter.cropInYear(2025), 'corn');

      final String? reason = constraints.rotationReason(
        field: northQuarter,
        crop: farm.crop('corn')!,
        planYear: farm.planYear,
      );

      expect(reason, isNotNull);
      expect(reason, contains('North Quarter'));
    });

    test('a crop returning after its rest period is allowed', () {
      final Farm farm = loadDemoFarm();
      final FarmField westField = farm.field('f_west_field')!;
      // Corn last grew here in 2024, two seasons before the 2026 plan year.
      expect(westField.seasonsSince('corn', farm.planYear), 2);

      expect(
        constraints.rotationReason(
          field: westField,
          crop: farm.crop('corn')!,
          planYear: farm.planYear,
        ),
        isNull,
      );
    });

    test('a field with no history for a crop is unconstrained', () {
      final Farm farm = loadDemoFarm();
      final FarmField westField = farm.field('f_west_field')!;
      expect(westField.seasonsSince('grain_sorghum', farm.planYear), isNull);

      expect(
        constraints.rotationReason(
          field: westField,
          crop: farm.crop('grain_sorghum')!,
          planYear: farm.planYear,
        ),
        isNull,
      );
    });

    test('the demo farm current plan breaks rotation on exactly one field', () {
      final Farm farm = loadDemoFarm();
      final List<RotationConflict> conflicts = constraints.rotationConflicts(
        farm: farm,
        allocation: farm.currentAllocation,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.fieldId, 'f_north_quarter');
      expect(conflicts.single.cropId, 'corn');
    });
  });

  group('pairing rules', () {
    test('a crop needing irrigation is refused on dryland', () {
      final Farm farm = loadDemoFarm();
      final CropProfile alfalfa = farm.crop('alfalfa')!;
      expect(alfalfa.requiresIrrigation, isTrue);

      expect(
        constraints.isPairingAllowed(
          farm: farm,
          field: farm.field('f_south_ridge')!,
          crop: alfalfa,
          enforceRotation: false,
        ),
        isFalse,
      );
    });

    test('a crop is refused on an incompatible soil', () {
      final Farm farm = loadDemoFarm();
      final FarmField riverBottom = farm.field('f_river_bottom')!;
      expect(riverBottom.irrigated, isTrue);
      expect(riverBottom.soilType, 'sandy loam');

      expect(
        constraints.isPairingAllowed(
          farm: farm,
          field: riverBottom,
          crop: farm.crop('alfalfa')!,
          enforceRotation: false,
        ),
        isFalse,
      );
    });

    test('a crop with no soil restrictions is allowed anywhere', () {
      final Farm farm = loadDemoFarm();
      final CropProfile sorghum = farm.crop('grain_sorghum')!;
      expect(sorghum.compatibleSoilTypes, isEmpty);

      for (final FarmField field in farm.fields) {
        expect(
          constraints.isPairingAllowed(
            farm: farm,
            field: field,
            crop: sorghum,
            enforceRotation: false,
          ),
          isTrue,
          reason: 'sorghum should be allowed on ${field.id}',
        );
      }
    });

    test('a hard restricted-input ban removes the tagged crops', () {
      final Farm farm = loadDemoFarm();
      final Farm banned = farm.copyWith(
        constraints: <FarmConstraint>[
          ...farm.constraints,
          const FarmConstraint(
            id: 'c_no_synthetic_n',
            type: ConstraintType.restrictedInput,
            mode: ConstraintMode.hard,
            numericValue: 0,
            textValue: 'synthetic_nitrogen',
          ),
        ],
      );

      expect(
        constraints.hardRestrictedTags(banned),
        contains('synthetic_nitrogen'),
      );
      expect(
        constraints.isPairingAllowed(
          farm: banned,
          field: banned.field('f_west_field')!,
          crop: banned.crop('corn')!,
          enforceRotation: false,
          restrictedTags: constraints.hardRestrictedTags(banned),
        ),
        isFalse,
      );
      // Soybeans carry no synthetic nitrogen tag, so they survive the ban.
      expect(
        constraints.isPairingAllowed(
          farm: banned,
          field: banned.field('f_south_ridge')!,
          crop: banned.crop('soybeans')!,
          enforceRotation: false,
          restrictedTags: constraints.hardRestrictedTags(banned),
        ),
        isTrue,
      );
    });
  });

  group('evaluation', () {
    test('the demo current plan reports its known violations', () {
      final Farm farm = loadDemoFarm();
      final List<ConstraintViolation> violations = evaluate(
        farm,
        farm.currentAllocation,
      );

      final Set<ConstraintType> types = violations
          .map((ConstraintViolation v) => v.type)
          .toSet();

      // One hard rule broken: corn follows corn on North Quarter.
      expect(types, contains(ConstraintType.rotationRequired));
      // And every preference the farmer set is missed.
      expect(types, contains(ConstraintType.minCashAfterDebtService));
      expect(types, contains(ConstraintType.maxCropConcentration));
      expect(types, contains(ConstraintType.minDebtServiceCoverage));
      expect(types, contains(ConstraintType.minSoilCoverShare));

      // The farm stays inside its water, nitrogen and expense ceilings.
      expect(types, isNot(contains(ConstraintType.maxWaterAcreInches)));
      expect(types, isNot(contains(ConstraintType.maxNitrogenLbs)));
      expect(types, isNot(contains(ConstraintType.maxOperatingExpense)));
    });

    test('disabled constraints are not evaluated at all', () {
      final Farm farm = loadDemoFarm();
      final Farm disabled = farm.copyWith(
        constraints: farm.constraints
            .map(
              (FarmConstraint c) => c.copyWith(mode: ConstraintMode.disabled),
            )
            .toList(),
      );

      expect(evaluate(disabled, disabled.currentAllocation), isEmpty);
    });

    test('a violation reports how far past the limit the plan landed', () {
      final Farm farm = loadDemoFarm();
      final ConstraintViolation concentration =
          evaluate(farm, farm.currentAllocation).firstWhere(
            (ConstraintViolation v) =>
                v.type == ConstraintType.maxCropConcentration,
          );

      // 635 of 900 acres are corn against a 50% preference.
      expect(concentration.actual, closeTo(635 / 900, 1e-9));
      expect(concentration.limit, 0.5);
      expect(concentration.overage, closeTo(635 / 900 - 0.5, 1e-9));
      expect(concentration.isHard, isFalse);
    });

    test('a farm with no debt is not failed by a coverage requirement', () {
      final Farm farm = loadDemoFarm();
      final Farm debtFree = farm.copyWith(debts: const <Never>[]);

      final List<ConstraintViolation> violations = evaluate(
        debtFree,
        debtFree.currentAllocation,
      );

      expect(
        violations.where(
          (ConstraintViolation v) =>
              v.type == ConstraintType.minDebtServiceCoverage,
        ),
        isEmpty,
      );
    });
  });
}
