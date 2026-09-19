import 'package:farmtwin/domain/engines/pareto_engine.dart';
import 'package:farmtwin/domain/models/crop_allocation.dart';
import 'package:farmtwin/domain/models/evaluated_plan.dart';
import 'package:farmtwin/domain/models/objective.dart';
import 'package:farmtwin/domain/models/plan_financials.dart';
import 'package:farmtwin/domain/models/plan_resources.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a plan carrying only the objective values a dominance test needs.
EvaluatedPlan plan({
  required String id,
  required double profit,
  required double water,
  double resilience = 0,
}) => EvaluatedPlan(
  allocation: CropAllocation(<String, String>{'f': id}),
  financials: PlanFinancials(
    totalAcres: 100,
    totalRevenue: 0,
    seedExpense: 0,
    fertilizerExpense: 0,
    chemicalExpense: 0,
    waterExpense: 0,
    laborExpense: 0,
    fuelExpense: 0,
    equipmentExpense: 0,
    fixedExpense: 0,
    debtService: 0,
    debtInterest: 0,
    acresByCrop: const <String, double>{},
    revenueByCrop: const <String, double>{},
    contributionMarginByCrop: const <String, double>{},
    productionByCrop: const <String, double>{},
    breakEvenPriceByCrop: const <String, double>{},
    breakEvenYieldByCrop: const <String, double>{},
  ),
  resources: const PlanResources(
    totalAcres: 100,
    waterAcreInches: 0,
    nitrogenLbs: 0,
    soilCoverAcres: 0,
    irrigatedAcresPlanted: 0,
    acresByCrop: <String, double>{},
    acresByInputTag: <String, double>{},
  ),
  cells: const <Never>[],
  rawObjectives: <ObjectiveType, double>{
    ObjectiveType.expectedProfit: profit,
    // Stored negated, matching the engine: less water is a higher score.
    ObjectiveType.waterEfficiency: -water,
    ObjectiveType.financialResilience: resilience,
  },
  violations: const <Never>[],
  preferenceConstraintCount: 0,
);

void main() {
  const ParetoEngine pareto = ParetoEngine();
  const List<ObjectiveType> twoObjectives = <ObjectiveType>[
    ObjectiveType.expectedProfit,
    ObjectiveType.waterEfficiency,
  ];

  group('dominance', () {
    test('better on every objective dominates', () {
      final EvaluatedPlan strong = plan(id: 'a', profit: 100, water: 10);
      final EvaluatedPlan weak = plan(id: 'b', profit: 50, water: 20);

      expect(pareto.dominates(strong, weak, twoObjectives), isTrue);
      expect(pareto.dominates(weak, strong, twoObjectives), isFalse);
    });

    test('equal everywhere but better on one objective dominates', () {
      final EvaluatedPlan a = plan(id: 'a', profit: 100, water: 10);
      final EvaluatedPlan b = plan(id: 'b', profit: 100, water: 20);

      expect(pareto.dominates(a, b, twoObjectives), isTrue);
    });

    test('identical plans do not dominate each other', () {
      final EvaluatedPlan a = plan(id: 'a', profit: 100, water: 10);
      final EvaluatedPlan b = plan(id: 'b', profit: 100, water: 10);

      expect(pareto.dominates(a, b, twoObjectives), isFalse);
      expect(pareto.dominates(b, a, twoObjectives), isFalse);
    });

    test('a genuine tradeoff is not dominance', () {
      final EvaluatedPlan profitable = plan(id: 'a', profit: 100, water: 30);
      final EvaluatedPlan frugal = plan(id: 'b', profit: 60, water: 5);

      expect(pareto.dominates(profitable, frugal, twoObjectives), isFalse);
      expect(pareto.dominates(frugal, profitable, twoObjectives), isFalse);
    });
  });

  group('frontier', () {
    test('dominated plans are removed and tradeoffs are kept', () {
      final List<EvaluatedPlan> plans = <EvaluatedPlan>[
        plan(id: 'high_profit', profit: 100, water: 30),
        plan(id: 'balanced', profit: 80, water: 15),
        plan(id: 'frugal', profit: 60, water: 5),
        // Beaten by 'balanced' on both counts.
        plan(id: 'dominated', profit: 70, water: 25),
      ];

      final List<EvaluatedPlan> front = pareto.frontier(
        plans: plans,
        objectives: twoObjectives,
      );

      final List<String> ids = front
          .map((EvaluatedPlan p) => p.allocation.cropFor('f')!)
          .toList();

      expect(ids, hasLength(3));
      expect(ids, isNot(contains('dominated')));
    });

    test('no plan on the frontier dominates another', () {
      final List<EvaluatedPlan> plans = <EvaluatedPlan>[
        for (int i = 0; i < 40; i++)
          plan(
            id: 'p$i',
            profit: (i * 7919) % 100 + 0.0,
            water: (i * 104729) % 60 + 0.0,
            resilience: (i * 1299709) % 30 + 0.0,
          ),
      ];

      final List<EvaluatedPlan> front = pareto.frontier(
        plans: plans,
        objectives: <ObjectiveType>[
          ...twoObjectives,
          ObjectiveType.financialResilience,
        ],
      );

      for (final EvaluatedPlan a in front) {
        for (final EvaluatedPlan b in front) {
          if (identical(a, b)) continue;
          expect(
            pareto.dominates(a, b, <ObjectiveType>[
              ...twoObjectives,
              ObjectiveType.financialResilience,
            ]),
            isFalse,
            reason: '${a.signature} dominates ${b.signature}',
          );
        }
      }
    });

    test('nothing outside the frontier beats everything on it', () {
      final List<EvaluatedPlan> plans = <EvaluatedPlan>[
        for (int i = 0; i < 60; i++)
          plan(
            id: 'p$i',
            profit: (i * 31) % 50 + 0.0,
            water: (i * 17) % 40 + 0.0,
          ),
      ];

      final List<EvaluatedPlan> front = pareto.frontier(
        plans: plans,
        objectives: twoObjectives,
      );
      final Set<String> frontIds = front
          .map((EvaluatedPlan p) => p.signature)
          .toSet();

      // Every excluded plan must be dominated by at least one that survived,
      // which is the other half of correctness: the filter must not drop a
      // plan that nothing beats.
      for (final EvaluatedPlan candidate in plans) {
        if (frontIds.contains(candidate.signature)) continue;
        expect(
          front.any(
            (EvaluatedPlan winner) =>
                pareto.dominates(winner, candidate, twoObjectives),
          ),
          isTrue,
          reason: '${candidate.signature} was dropped but nothing dominates it',
        );
      }
    });

    test('an empty candidate set yields an empty frontier', () {
      expect(
        pareto.frontier(
          plans: const <EvaluatedPlan>[],
          objectives: twoObjectives,
        ),
        isEmpty,
      );
    });
  });

  group('thinning', () {
    test('a frontier under the limit is returned untouched', () {
      final List<EvaluatedPlan> front = <EvaluatedPlan>[
        plan(id: 'a', profit: 3, water: 1),
        plan(id: 'b', profit: 2, water: 2),
      ];

      expect(pareto.thin(frontier: front, limit: 10), same(front));
    });

    test('thinning keeps both extremes', () {
      final List<EvaluatedPlan> front = <EvaluatedPlan>[
        for (int i = 0; i < 50; i++)
          plan(id: 'p$i', profit: 50.0 - i, water: i + 0.0),
      ];

      final List<EvaluatedPlan> thinned = pareto.thin(
        frontier: front,
        limit: 7,
      );

      expect(thinned, hasLength(7));
      expect(thinned.first.signature, front.first.signature);
      expect(thinned.last.signature, front.last.signature);
    });
  });
}
