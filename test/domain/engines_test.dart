import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:farmtwin/domain/farm_domain.dart';

final provenance = Provenance(
  source: DataSourceType.userEntered,
  updatedAt: DateTime.utc(2026),
);
CropProfile crop(
  String id, {
  double price = 5,
  double yield = 10,
  double seed = 2,
  double water = 1,
  double nitrogen = 1,
  String? family,
  int rotation = 0,
  double yieldVolatility = 0,
  double priceVolatility = 0,
}) => CropProfile(
  id: id,
  name: id,
  yieldPerAcre: yield,
  pricePerUnit: price,
  yieldUnit: 'unit',
  seedCostPerAcre: seed,
  fertilizerCostPerAcre: 0,
  chemicalCostPerAcre: 0,
  waterCostPerAcre: 0,
  laborCostPerAcre: 0,
  fuelCostPerAcre: 0,
  equipmentCostPerAcre: 0,
  waterPerAcre: water,
  nitrogenPerAcre: nitrogen,
  yieldVolatility: yieldVolatility,
  priceVolatility: priceVolatility,
  rotationFamily: family ?? id,
  minimumRotationYears: rotation,
  requiresIrrigation: false,
  inputs: const [],
  providesSoilCover: false,
  provenance: provenance,
);
SimulationConfig simulation({
  int iterations = 2000,
  int seed = 42,
  double weather = 0,
  double market = 0,
}) => SimulationConfig(
  iterations: iterations,
  seed: seed,
  weatherCorrelation: weather,
  marketCorrelation: market,
  fertilizerVolatility: 0,
  fuelVolatility: 0,
  waterVolatility: 0,
  equipmentFailureProbability: 0,
  equipmentFailureCost: 0,
);
Farm fixture({
  List<CropProfile>? crops,
  List<Field>? fields,
  List<Expense> expenses = const [],
  List<Debt> debts = const [],
  List<FarmConstraint> constraints = const [],
  Map<Objective, double> weights = const {Objective.profit: 1},
  int exhaustiveLimit = 1000,
  int candidateLimit = 1000,
  int frontierLimit = 1000,
}) {
  final choices = crops ?? [crop('a'), crop('b', price: 8, water: 3)];
  return Farm(
    id: 'test',
    name: 'Unseen test farm',
    fields:
        fields ??
        [
          Field(
            id: 'f1',
            name: 'Field One',
            acres: 10,
            currentCropId: choices.first.id,
            compatibleCropIds: choices.map((c) => c.id).toList(),
            provenance: provenance,
          ),
        ],
    crops: choices,
    expenses: expenses,
    debts: debts,
    constraints: constraints,
    settings: FarmSettings(
      currencyCode: 'USD',
      optimization: OptimizationConfig(
        weights: weights,
        exhaustiveLimit: exhaustiveLimit,
        candidateLimit: candidateLimit,
        frontierLimit: frontierLimit,
        seed: 7,
      ),
      simulation: simulation(),
      priceGrowthRate: 0,
      expenseInflationRate: 0,
      liquidityReserve: 0,
      alertUtilizationThreshold: .9,
    ),
    provenance: provenance,
  );
}

FarmConstraint rule(
  ConstraintKind kind,
  double limit, {
  ConstraintMode mode = ConstraintMode.hard,
}) => FarmConstraint(
  id: kind.name,
  name: kind.name,
  kind: kind,
  mode: mode,
  limit: limit,
);

void main() {
  group('financial calculations', () {
    test(
      'revenue, full cost, amortized debt and break-even are independently calculated',
      () {
        final c = crop('a', yield: 20, price: 3, seed: 4).copyWith(
          fertilizerCostPerAcre: 5,
          chemicalCostPerAcre: 6,
          waterCostPerAcre: 7,
          laborCostPerAcre: 8,
          fuelCostPerAcre: 9,
          equipmentCostPerAcre: 10,
        );
        final farm = fixture(
          crops: [c],
          expenses: [
            Expense(
              id: 'fixed',
              name: 'Rent',
              annualAmount: 100,
              inflationRate: 0,
              provenance: provenance,
            ),
          ],
          debts: [
            Debt(
              id: 'loan',
              name: 'Loan',
              balance: 1000,
              annualInterestRate: .1,
              annualPayment: 150,
              provenance: provenance,
            ),
          ],
        );
        final r = const FinancialEngine().evaluate(farm, farm.currentPlan);
        expect(r.revenue, 600);
        expect(r.variableExpense, 490);
        expect(r.operatingExpense, 590);
        expect(r.contributionMargin, 110);
        expect(r.operatingIncome, 10);
        expect(r.debtService, 150);
        expect(r.cashAfterDebt, -140);
        expect(r.marginPerAcre, 1);
        expect(r.debtCoverage, closeTo(10 / 150, 1e-12));
        expect(r.fields.single.breakEvenPrice, 2.95);
        expect(r.fields.single.breakEvenYield, closeTo(590 / 30, 1e-12));
        expect(
          r.costBreakdown.values.reduce((a, b) => a + b),
          r.operatingExpense,
        );
        expect(farm.debts.single.nextBalance, 950);
      },
    );
    test(
      'zero price, zero yield and no debt yield explicit undefined ratios',
      () {
        final farm = fixture(crops: [crop('a', price: 0, yield: 0)]);
        final r = const FinancialEngine().evaluate(farm, farm.currentPlan);
        expect(r.fields.single.breakEvenPrice, isNull);
        expect(r.fields.single.breakEvenYield, isNull);
        expect(r.debtCoverage, isNull);
        expect(() => jsonEncode(r.toJson()), returnsNormally);
      },
    );
    test('debt payoff never exceeds principal plus accrued interest', () {
      final debt = Debt(
        id: 'd',
        name: 'Debt',
        balance: 100,
        annualInterestRate: .1,
        annualPayment: 500,
        provenance: provenance,
      );
      expect(debt.paymentDue, closeTo(110, 1e-12));
      expect(debt.nextBalance, 0);
    });
  });
  group('domain input validation and persistence', () {
    test(
      'roundtrip preserves immutable farm including provenance and scenarios',
      () {
        final farm = fixture().copyWith(
          scenarios: [
            StressScenario(id: 's', name: 'Shock', priceMultiplier: .5),
          ],
        );
        final roundtrip = Farm.fromJson(
          jsonDecode(jsonEncode(farm.toJson())) as Map<String, dynamic>,
        );
        expect(roundtrip.toJson(), farm.toJson());
        expect(() => roundtrip.fields.clear(), throwsUnsupportedError);
        expect(
          () => roundtrip.settings.optimization.weights.clear(),
          throwsUnsupportedError,
        );
      },
    );
    test('missing numeric data does not become a silent business default', () {
      final json = fixture().crops.first.toJson()..remove('pricePerUnit');
      expect(
        () => CropProfile.fromJson(json),
        throwsA(isA<ValidationFailure>()),
      );
    });
    test(
      'nonfinite, negative acreage and invalid objective weights fail in domain',
      () {
        final farm = fixture();
        for (final acres in [-1.0, 0.0, double.nan, double.infinity]) {
          final invalid = farm.copyWith(
            fields: [farm.fields.first.copyWith(acres: acres)],
          );
          expect(
            () =>
                const FinancialEngine().evaluate(invalid, invalid.currentPlan),
            throwsA(isA<ValidationFailure>()),
          );
        }
        expect(
          () => fixture(weights: {Objective.profit: .5}).validate(),
          throwsA(isA<ValidationFailure>()),
        );
        expect(
          () => farm
              .copyWith(crops: [farm.crops.first.copyWith(pricePerUnit: -1)])
              .validate(),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
    test(
      'empty farm may persist but cannot calculate; incompatible plan rejected',
      () {
        final farm = fixture();
        final empty = farm.copyWith(fields: [], crops: []);
        expect(() => empty.validate(), returnsNormally);
        expect(
          () => const OptimizationEngine().run(empty),
          throwsA(isA<DataUnavailableFailure>()),
        );
        expect(
          () => const FinancialEngine().evaluate(
            farm,
            FarmPlan(assignments: {'f1': 'missing'}),
          ),
          throwsA(isA<DataUnavailableFailure>()),
        );
      },
    );
    test(
      'compatible current crop uses stable IDs despite display name changes',
      () {
        final corn = crop('crop-corn-id').copyWith(name: 'Corn');
        final farm = fixture(crops: [corn]);
        expect(() => farm.validate(requireReady: true), returnsNormally);
        expect(farm.fields.single.isCompatibleWith(corn), isTrue);
        expect(
          () => farm
              .copyWith(crops: [corn.copyWith(name: 'Sweet corn')])
              .validate(requireReady: true),
          returnsNormally,
        );
        expect(
          () => farm
              .copyWith(
                fields: [farm.fields.single.copyWith(currentCropId: 'Corn')],
              )
              .validate(),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
    test(
      'a current crop outside compatibility is rejected before persistence',
      () {
        final farm = fixture();
        final field = farm.fields.single.copyWith(compatibleCropIds: ['b']);
        expect(field.isCompatibleWith(farm.crop('a')), isFalse);
        expect(() => field.validate(), throwsA(isA<ValidationFailure>()));
        expect(
          () => farm.copyWith(fields: [field]).validate(),
          throwsA(isA<ValidationFailure>()),
        );
        expect(
          () => farm
              .copyWith(fields: [field.copyWith(currentCropId: 'b')])
              .validatePlan(FarmPlan(assignments: {field.id: 'a'})),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );
    test('current and compatible crop IDs must resolve to real profiles', () {
      final farm = fixture();
      final unknown = farm.fields.single.copyWith(
        currentCropId: 'missing-profile',
        compatibleCropIds: ['missing-profile'],
      );
      expect(
        () => farm.copyWith(fields: [unknown]).validate(),
        throwsA(isA<DataUnavailableFailure>()),
      );
    });
    test(
      'irrigation requirement also applies before saving a current crop',
      () {
        final corn = crop(
          'corn-id',
        ).copyWith(name: 'Corn', requiresIrrigation: true);
        final farm = fixture(crops: [corn]);
        final dryField = farm.fields.single.copyWith(irrigated: false);
        expect(dryField.isCompatibleWith(corn), isFalse);
        expect(
          () => farm.copyWith(fields: [dryField]).validate(),
          throwsA(
            isA<ValidationFailure>().having(
              (failure) => failure.message,
              'actionable reason',
              contains('requires irrigation'),
            ),
          ),
        );
        expect(
          () => farm
              .copyWith(fields: [dryField.copyWith(irrigated: true)])
              .validate(),
          returnsNormally,
        );
      },
    );
    test(
      'unassigned field with no compatible crops can persist without calculating',
      () {
        final farm = fixture();
        final field = farm.fields.single.copyWith(
          currentCropId: '',
          compatibleCropIds: [],
        );
        final incomplete = farm.copyWith(fields: [field]);
        expect(() => incomplete.validate(), returnsNormally);
        final restored = Farm.fromJson(incomplete.toJson());
        expect(() => restored.validate(), returnsNormally);
        expect(restored.fields.single.currentCropId, isEmpty);
        expect(restored.fields.single.compatibleCropIds, isEmpty);
        expect(
          () => const OptimizationEngine().run(restored),
          throwsA(
            isA<ValidationFailure>().having(
              (failure) => failure.message,
              'missing configuration',
              contains('Set current crop and compatible crops'),
            ),
          ),
        );
      },
    );
    test('future schema is a typed failure', () {
      expect(
        () => fixture().copyWith(schemaVersion: 999).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
  group('constraints and optimizer', () {
    for (final exhaustive in [true, false]) {
      test(
        '${exhaustive ? 'exhaustive' : 'bounded'} optimizer assigns only compatible crop IDs',
        () {
          final crops = [
            crop('dry-a', price: 2).copyWith(name: 'Corn'),
            crop('dry-b', price: 3).copyWith(name: 'Corn'),
            crop('irrigated', price: 100).copyWith(requiresIrrigation: true),
            crop('never-selected', price: 999),
          ];
          final farm = fixture(
            crops: crops,
            exhaustiveLimit: exhaustive ? 100 : 1,
            fields: [
              Field(
                id: 'dry-field',
                name: 'Dry field',
                acres: 10,
                currentCropId: 'dry-a',
                compatibleCropIds: ['dry-a', 'dry-b', 'irrigated'],
                irrigated: false,
                provenance: provenance,
              ),
              Field(
                id: 'wet-field',
                name: 'Irrigated field',
                acres: 10,
                currentCropId: 'dry-b',
                compatibleCropIds: ['dry-b', 'irrigated'],
                irrigated: true,
                provenance: provenance,
              ),
            ],
          );
          final result = const OptimizationEngine().run(farm);
          expect(result.diagnostics.searchSpace, '4');
          expect(result.diagnostics.approximate, !exhaustive);
          expect(result.diagnostics.candidatesGenerated, 4);
          expect(result.recommended!.plan.assignments, {
            'dry-field': 'dry-b',
            'wet-field': 'irrigated',
          });
          for (final evaluated in [
            result.current,
            result.recommended!,
            ...result.pareto,
            ...result.representatives.values,
          ]) {
            for (final entry in evaluated.plan.assignments.entries) {
              expect(
                farm.field(entry.key).isCompatibleWith(farm.crop(entry.value)),
                isTrue,
              );
            }
          }
        },
      );
    }
    test(
      'large requested budgets respect disclosed field-result and Pareto work ceilings',
      () {
        final fields = List.generate(
          maximumOptimizationFields,
          (i) => Field(
            id: 'f$i',
            name: 'Field $i',
            acres: 1,
            currentCropId: 'a',
            compatibleCropIds: ['a', 'b'],
            provenance: provenance,
          ),
        );
        final farm = fixture(
          fields: fields,
          exhaustiveLimit: 1000000,
          candidateLimit: 1000000,
        );
        final run = const OptimizationEngine().run(farm);
        expect(run.diagnostics.approximate, isTrue);
        expect(
          run.diagnostics.candidatesGenerated * fields.length,
          lessThanOrEqualTo(maximumRetainedFieldEvaluations),
        );
        expect(
          run.diagnostics.candidatesGenerated *
              farm.settings.optimization.frontierLimit,
          lessThanOrEqualTo(maximumParetoComparisons),
        );
        expect(
          run.warnings.any(
            (w) => w.contains('device work and memory ceilings'),
          ),
          isTrue,
        );
        expect(run.recommended, isNotNull);
        expect(run.recommended!.plan.assignments.length, fields.length);
      },
    );
    test(
      'models exceeding supported dimensions fail before generating candidates',
      () {
        final fields = List.generate(
          maximumOptimizationFields + 1,
          (i) => Field(
            id: 'f$i',
            name: 'Field $i',
            acres: 1,
            currentCropId: 'a',
            compatibleCropIds: ['a', 'b'],
            provenance: provenance,
          ),
        );
        expect(
          () => const OptimizationEngine().run(fixture(fields: fields)),
          throwsA(isA<OptimizationFailure>()),
        );
      },
    );
    test(
      'hard limits include exact boundary, preferences do not invalidate',
      () {
        final farm = fixture(
          constraints: [
            rule(ConstraintKind.maxWater, 10),
            rule(
              ConstraintKind.minOperatingIncome,
              10000,
              mode: ConstraintMode.preference,
            ),
          ],
        );
        final finances = const FinancialEngine().evaluate(
          farm,
          farm.currentPlan,
        );
        final report = const ConstraintEngine().evaluate(
          farm,
          farm.currentPlan,
          finances,
        );
        expect(report.feasible, isTrue);
        expect(report.satisfied, 1);
        expect(report.total, 2);
        final invalid = farm.copyWith(
          constraints: [rule(ConstraintKind.maxWater, 9.99)],
        );
        expect(
          const ConstraintEngine()
              .evaluate(invalid, invalid.currentPlan, finances)
              .feasible,
          isFalse,
        );
      },
    );
    test(
      'exhaustive search actual counts and optimum agree with hand enumeration',
      () {
        final farm = fixture(
          fields: [
            Field(
              id: 'f1',
              name: 'One',
              acres: 10,
              currentCropId: 'a',
              compatibleCropIds: ['a', 'b'],
              provenance: provenance,
            ),
            Field(
              id: 'f2',
              name: 'Two',
              acres: 20,
              currentCropId: 'a',
              compatibleCropIds: ['a', 'b'],
              provenance: provenance,
            ),
          ],
          constraints: [rule(ConstraintKind.maxWater, 50)],
        );
        final progress = <OptimizationProgress>[];
        final run = const OptimizationEngine().run(
          farm,
          onProgress: progress.add,
        );
        // AA: water30,income1440; BA: water50,income1740;
        // AB: water70,income2040; BB: water90,income2340.
        expect(run.diagnostics.searchSpace, '4');
        expect(run.diagnostics.candidatesGenerated, 4);
        expect(run.diagnostics.plansEvaluated, 4);
        expect(run.diagnostics.candidatesPruned, 2);
        expect(run.diagnostics.feasiblePlans, 2);
        expect(run.recommended!.plan.assignments, {'f1': 'b', 'f2': 'a'});
        expect(run.recommended!.financial.operatingIncome, 1740);
        expect(run.recommended!.score, 1);
        expect(run.diagnostics.approximate, isFalse);
        expect(progress.last.generated, 4);
      },
    );
    test(
      'normalization and changed weights change the calculated selection',
      () {
        final farm = fixture(
          weights: {Objective.profit: .8, Objective.waterEfficiency: .2},
        );
        expect(
          const OptimizationEngine()
              .run(farm)
              .recommended!
              .plan
              .assignments['f1'],
          'b',
        );
        final lowWater = farm.copyWith(
          settings: farm.settings.copyWith(
            optimization: farm.settings.optimization.copyWith(
              weights: {Objective.profit: .2, Objective.waterEfficiency: .8},
            ),
          ),
        );
        final run = const OptimizationEngine().run(lowWater);
        expect(run.recommended!.plan.assignments['f1'], 'a');
        expect(run.pareto.length, 2);
        expect(run.recommended!.score, closeTo(.8, 1e-12));
      },
    );
    test('known Pareto vectors distinguish domination and equality', () {
      final axes = [Objective.profit, Objective.waterEfficiency];
      expect(
        OptimizationEngine.dominates(
          {Objective.profit: 2, Objective.waterEfficiency: 3},
          {Objective.profit: 1, Objective.waterEfficiency: 2},
          axes,
        ),
        isTrue,
      );
      expect(
        OptimizationEngine.dominates(
          {Objective.profit: 2, Objective.waterEfficiency: 1},
          {Objective.profit: 1, Objective.waterEfficiency: 2},
          axes,
        ),
        isFalse,
      );
      expect(
        OptimizationEngine.dominates(
          {Objective.profit: 2, Objective.waterEfficiency: 1},
          {Objective.profit: 2, Objective.waterEfficiency: 1},
          axes,
        ),
        isFalse,
      );
    });
    test('rotation and restrictions prune before financial evaluation', () {
      final a = crop('a', family: 'same', rotation: 1),
          b = crop(
            'b',
            family: 'other',
            rotation: 1,
          ).copyWith(inputs: ['blocked']);
      final farm = fixture(
        crops: [a, b],
        fields: [
          Field(
            id: 'f1',
            name: 'One',
            acres: 10,
            currentCropId: 'a',
            compatibleCropIds: ['a', 'b'],
            cropHistory: ['a'],
            provenance: provenance,
          ),
        ],
        constraints: [
          rule(ConstraintKind.rotation, 0),
          FarmConstraint(
            id: 'restricted',
            name: 'Restricted',
            kind: ConstraintKind.restrictedInputs,
            mode: ConstraintMode.hard,
            limit: 0,
            restrictedInputs: ['blocked'],
          ),
        ],
      );
      final run = const OptimizationEngine().run(farm);
      expect(run.recommended, isNull);
      expect(run.diagnostics.candidatesPruned, 2);
      expect(run.diagnostics.plansEvaluated, 0);
    });
    test(
      'large search uses deterministic bounded strategy and exposes approximation',
      () {
        final fields = List.generate(
          12,
          (i) => Field(
            id: 'f$i',
            name: 'Field $i',
            acres: 1,
            currentCropId: 'a',
            compatibleCropIds: ['a', 'b'],
            provenance: provenance,
          ),
        );
        final farm = fixture(
          fields: fields,
          exhaustiveLimit: 4,
          candidateLimit: 64,
        );
        final first = const OptimizationEngine().run(farm),
            second = const OptimizationEngine().run(farm);
        expect(first.diagnostics.searchSpace, '4096');
        expect(first.diagnostics.approximate, isTrue);
        expect(first.diagnostics.candidatesGenerated, lessThanOrEqualTo(64));
        expect(
          first.recommended!.plan.toJson(),
          second.recommended!.plan.toJson(),
        );
        expect(
          first.diagnostics.candidatesGenerated,
          second.diagnostics.candidatesGenerated,
        );
      },
    );
    test(
      'all returned tradeoffs satisfy hard constraints and are nondominated',
      () {
        final farm = fixture(
          weights: {Objective.profit: .5, Objective.waterEfficiency: .5},
        );
        final run = const OptimizationEngine().run(farm);
        for (final candidate in run.pareto) {
          expect(candidate.constraints.feasible, isTrue);
          for (final other in run.pareto) {
            expect(
              OptimizationEngine.dominates(
                other.objectives,
                candidate.objectives,
                farm.settings.optimization.weights.keys,
              ),
              isFalse,
            );
          }
        }
      },
    );
  });
  group('risk simulation', () {
    test(
      'splitting an identical crop does not reduce shared commodity risk',
      () {
        final original = fixture(crops: [crop('a', priceVolatility: .25)]);
        final split = original.copyWith(
          fields: [
            original.fields.first.copyWith(id: 'left', acres: 4),
            original.fields.first.copyWith(id: 'right', acres: 6),
          ],
        );
        final one = const OptimizationEngine().evaluate(
          original,
          original.currentPlan,
        );
        final two = const OptimizationEngine().evaluate(
          split,
          split.currentPlan,
        );
        expect(one.objectives[Objective.resilience], 355);
        expect(
          two.objectives[Objective.resilience],
          one.objectives[Objective.resilience],
        );
      },
    );
    test(
      'paired plans consume identical weather shocks despite crop mix changes',
      () {
        final original = fixture(
          crops: [
            crop('a', yieldVolatility: .2),
            crop('b', yieldVolatility: .2),
          ],
          fields: [
            Field(
              id: 'f1',
              name: 'One',
              acres: 4,
              currentCropId: 'a',
              compatibleCropIds: ['a', 'b'],
              provenance: provenance,
            ),
            Field(
              id: 'f2',
              name: 'Two',
              acres: 6,
              currentCropId: 'a',
              compatibleCropIds: ['a', 'b'],
              provenance: provenance,
            ),
          ],
        );
        final alternative = FarmPlan(assignments: {'f1': 'b', 'f2': 'a'});
        final one = const MonteCarloEngine().run(
          original,
          original.currentPlan,
        );
        final two = const MonteCarloEngine().run(original, alternative);
        expect(two.samples, one.samples);
      },
    );
    test(
      'zero variance collapses to independently calculated cash and one histogram bin',
      () {
        final farm = fixture();
        final result = const MonteCarloEngine().run(farm, farm.currentPlan);
        expect(result.mean, 480);
        expect(result.median, 480);
        expect(result.standardDeviation, 0);
        expect(result.p05, 480);
        expect(result.p95, 480);
        expect(result.positiveCashProbability, 1);
        expect(result.negativeCashProbability, 0);
        expect(result.histogram().single.count, result.iterations);
      },
    );
    test(
      'seed, quantiles, histogram and probabilities have reproducible invariants',
      () {
        final farm = fixture(
          crops: [crop('a', yieldVolatility: .25, priceVolatility: .3)],
        );
        final first = const MonteCarloEngine().run(farm, farm.currentPlan);
        final second = const MonteCarloEngine().run(farm, farm.currentPlan);
        final other = const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: simulation(seed: 43),
        );
        expect(first.samples, second.samples);
        expect(first.samples, isNot(other.samples));
        expect(first.p05, lessThan(first.p25));
        expect(first.p25, lessThan(first.median));
        expect(first.median, lessThan(first.p75));
        expect(first.p75, lessThan(first.p95));
        expect(
          first.histogram().fold(0, (sum, bin) => sum + bin.count),
          first.iterations,
        );
        expect(
          first.positiveCashProbability + first.negativeCashProbability,
          closeTo(1, 1e-12),
        );
        expect(first.mean, closeTo(480, 40));
        expect(first.toJson().containsKey('samples'), isFalse);
      },
    );
    test(
      'mean-corrected lognormal yield reproduces independent analytic moments',
      () {
        final farm = fixture(crops: [crop('a', yieldVolatility: .2)]);
        final result = const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: simulation(iterations: 20000),
        );
        // Revenue expectation 500; revenue SD = CV * expected revenue = 100.
        expect(result.mean, closeTo(480, 3));
        expect(result.standardDeviation, closeTo(100, 3));
      },
    );
    test(
      'shared weather increases aggregate variance versus independent fields',
      () {
        final farm = fixture(
          crops: [crop('a', yieldVolatility: .25)],
          fields: List.generate(
            8,
            (i) => Field(
              id: 'f$i',
              name: 'Field $i',
              acres: 1,
              currentCropId: 'a',
              compatibleCropIds: ['a'],
              provenance: provenance,
            ),
          ),
        );
        final independent = const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: simulation(iterations: 10000, weather: 0),
        );
        final correlated = const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: simulation(iterations: 10000, weather: 1),
        );
        expect(
          correlated.standardDeviation,
          greaterThan(independent.standardDeviation * 2),
        );
        expect(
          independent.standardDeviation,
          closeTo(50 * .25 * math.sqrt(8), 2),
        );
        expect(correlated.standardDeviation, closeTo(50 * .25 * 8, 4));
      },
    );
    test(
      'equipment probability one subtracts configured expense on every sample',
      () {
        final farm = fixture();
        final config = simulation().copyWith(
          equipmentFailureProbability: 1,
          equipmentFailureCost: 123,
        );
        final result = const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: config,
        );
        expect(result.mean, 357);
      },
    );
    test('invalid simulation configuration fails with typed failure', () {
      final farm = fixture();
      expect(
        () => const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: simulation(iterations: 1),
        ),
        throwsA(isA<SimulationFailure>()),
      );
      expect(
        () => const MonteCarloEngine().run(
          farm,
          farm.currentPlan,
          config: simulation(weather: 1.1),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
  group('scenario, multi-year and explanations', () {
    test(
      'explanations follow the selected plan and do not invent what-if calculations',
      () {
        final farm = fixture();
        final run = const OptimizationEngine().run(farm);
        final selected = const LocalExplanationEngine().explain(
          'Why did the allocation change?',
          farm,
          optimization: run,
          selected: run.current,
        );
        expect(selected, contains('Field One keeps a'));
        expect(selected, isNot(contains('changes from a to b')));
        final scenario = const LocalExplanationEngine().explain(
          'What if prices increase another 15%?',
          farm,
          optimization: run,
        );
        expect(scenario, contains('Scenario lab'));
        expect(scenario, contains('cannot infer an uncalculated scenario'));
      },
    );
    test('scenario transforms supplied assumptions and preserves original', () {
      final farm = fixture(
        crops: [crop('a').copyWith(fertilizerCostPerAcre: 10)],
        constraints: [rule(ConstraintKind.maxWater, 100)],
      );
      final scenario = StressScenario(
        id: 'custom',
        name: 'Custom',
        priceMultiplier: .5,
        yieldMultiplier: .8,
        fertilizerMultiplier: 1.2,
        waterAvailabilityMultiplier: .7,
        equipmentCostAddition: 50,
      );
      final result = const ScenarioEngine().apply(farm, scenario);
      expect(result.crops.single.pricePerUnit, 2.5);
      expect(result.crops.single.yieldPerAcre, 8);
      expect(result.crops.single.fertilizerCostPerAcre, 12);
      expect(result.constraints.single.limit, 70);
      expect(result.expenses.single.annualAmount, 50);
      expect(farm.crops.single.pricePerUnit, 5);
      expect(farm.expenses, isEmpty);
      expect(
        const FinancialEngine()
            .evaluate(result, result.currentPlan)
            .operatingIncome,
        10,
      );
    });
    test(
      'annual inflation, debt schedule and cumulative cash are actual recurrences',
      () {
        var farm = fixture(
          crops: [crop('a')],
          expenses: [
            Expense(
              id: 'rent',
              name: 'Rent',
              annualAmount: 100,
              inflationRate: .1,
              provenance: provenance,
            ),
          ],
          debts: [
            Debt(
              id: 'loan',
              name: 'Loan',
              balance: 100,
              annualInterestRate: .1,
              annualPayment: 60,
              provenance: provenance,
            ),
          ],
        );
        farm = farm.copyWith(
          settings: farm.settings.copyWith(
            priceGrowthRate: .1,
            expenseInflationRate: .2,
          ),
        );
        final p = const MultiYearEngine().project(
          farm,
          farm.currentPlan,
          years: 3,
        );
        // Yr1: 500 - 20 - 100 - 60 = 320; loan end50.
        // Yr2: 550 - 24 - 110 - 55 = 361; loan paid.
        // Yr3: 605 - 28.8 - 121 = 455.2.
        expect(p.years[0].financial.cashAfterDebt, closeTo(320, 1e-9));
        expect(p.years[0].endingDebt, closeTo(50, 1e-9));
        expect(p.years[1].financial.cashAfterDebt, closeTo(361, 1e-9));
        expect(p.years[1].endingDebt, 0);
        expect(p.years[2].financial.cashAfterDebt, closeTo(455.2, 1e-9));
        expect(p.cumulativeCash, closeTo(1136.2, 1e-9));
      },
    );
    test('rotation uses actual prior-year family histories', () {
      final farm = fixture(
        crops: [crop('a', rotation: 1), crop('b', rotation: 1)],
        constraints: [rule(ConstraintKind.rotation, 0)],
      );
      final projection = const MultiYearEngine().project(
        farm,
        farm.currentPlan,
        years: 3,
      );
      expect(projection.years.map((y) => y.plan.assignments['f1']), [
        'a',
        'b',
        'a',
      ]);
      expect(projection.years.map((y) => y.rotationChanges), [0, 1, 0]);
      expect(projection.years.every((y) => y.feasible), isTrue);
    });
    test(
      'alerts include source values and explanation responds to changed inputs',
      () {
        final farm = fixture(constraints: [rule(ConstraintKind.maxWater, 10)]);
        final r = const FinancialEngine().evaluate(farm, farm.currentPlan),
            c = const ConstraintEngine();
        final alerts = const AlertEngine().evaluate(
          farm,
          r,
          c.evaluate(farm, farm.currentPlan, r),
        );
        expect(alerts.single.sourceValues, {
          'actual': 10,
          'limit': 10,
          'utilization': 1,
          'alertThreshold': .9,
        });
        final first = const LocalExplanationEngine().explain(
          'Explain my cash',
          farm,
        );
        final changed = farm.copyWith(
          crops: farm.crops
              .map((c) => c.copyWith(pricePerUnit: c.pricePerUnit * 2))
              .toList(),
        );
        final second = const LocalExplanationEngine().explain(
          'Explain my cash',
          changed,
        );
        expect(first, contains('480.00'));
        expect(second, contains('980.00'));
        expect(first, isNot(second));
      },
    );
  });
  test(
    'sample contains only inputs; real optimization and constraint changes produce different outputs',
    () {
      final json =
          jsonDecode(File('test/fixtures/farm.json').readAsStringSync())
              as Map<String, dynamic>;
      final farm = Farm.fromJson(json);
      farm.validate(requireReady: true);
      final run = const OptimizationEngine().run(farm);
      expect(run.recommended, isNotNull);
      expect(run.recommended!.constraints.feasible, isTrue);
      expect(
        run.recommended!.financial.operatingIncome,
        greaterThan(run.current.financial.operatingIncome),
      );
      final changed = farm.copyWith(
        constraints: farm.constraints
            .map(
              (c) => c.kind == ConstraintKind.maxWater
                  ? c.copyWith(limit: c.limit * .6)
                  : c,
            )
            .toList(),
      );
      final changedRun = const OptimizationEngine().run(changed);
      expect(changedRun.recommended, isNotNull);
      expect(
        changedRun.recommended!.financial.waterUsage,
        lessThan(run.recommended!.financial.waterUsage),
      );
      final risk = const MonteCarloEngine().run(
        farm,
        run.recommended!.plan,
        config: farm.settings.simulation.copyWith(iterations: 2000),
      );
      expect(risk.samples.length, 2000);
      expect(risk.standardDeviation, greaterThan(0));
      expect(() => jsonEncode(run.toJson()), returnsNormally);
    },
  );
}
