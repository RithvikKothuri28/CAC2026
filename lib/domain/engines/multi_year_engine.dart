import '../models/farm_models.dart';
import '../models/results.dart';
import 'constraint_engine.dart';
import 'financial_engine.dart';

/// Projects a supplied plan, replacing rotation-incompatible assignments using
/// the highest annual contribution margin among compatible alternatives.
/// This is an explicit deterministic rotation schedule, not a global multi-year
/// optimum. Every year's hard constraints are checked and reported.
class MultiYearEngine {
  const MultiYearEngine();
  MultiYearProjection project(Farm farm, FarmPlan plan, {int years = 5}) {
    farm.validate(requireReady: true);
    farm.validatePlan(plan);
    if (years < 1 || years > 100) {
      throw const ValidationFailure(
        'Projection years must be between 1 and 100.',
      );
    }
    var state = farm;
    final result = <YearProjection>[];
    final warnings = <String>{};
    final enforceRotation = farm.constraints.any(
      (c) =>
          c.kind == ConstraintKind.rotation &&
          c.mode != ConstraintMode.disabled,
    );
    for (var year = 1; year <= years; year++) {
      final allocation = Map<String, String>.from(plan.assignments);
      var changes = 0, rotationFeasible = true;
      if (year > 1 && enforceRotation) {
        for (final field in state.fields) {
          final preferred = state.crop(allocation[field.id]!);
          if (const ConstraintEngine().rotationAllowed(
            state,
            field,
            preferred,
          )) {
            continue;
          }
          final choices =
              field.compatibleCropIds
                  .map(state.crop)
                  .where(
                    (c) =>
                        field.isCompatibleWith(c) &&
                        const ConstraintEngine().rotationAllowed(
                          state,
                          field,
                          c,
                        ),
                  )
                  .toList()
                ..sort((a, b) {
                  final marginA =
                      a.yieldPerAcre * field.yieldMultiplier * a.pricePerUnit -
                      a.costPerAcre;
                  final marginB =
                      b.yieldPerAcre * field.yieldMultiplier * b.pricePerUnit -
                      b.costPerAcre;
                  final order = marginB.compareTo(marginA);
                  return order == 0 ? a.id.compareTo(b.id) : order;
                });
          if (choices.isEmpty) {
            rotationFeasible = false;
            warnings.add(
              'Year $year: ${field.name} has no compatible crop satisfying its rotation interval. The preferred crop is shown as an infeasible projection.',
            );
          } else {
            allocation[field.id] = choices.first.id;
            changes++;
          }
        }
      }
      final annualPlan = FarmPlan(assignments: allocation);
      final financial = const FinancialEngine().evaluate(state, annualPlan);
      final report = const ConstraintEngine().evaluate(
        state,
        annualPlan,
        financial,
      );
      if (!report.feasible) {
        warnings.add(
          'Year $year violates hard constraints: ${report.checks.where((c) => !c.satisfied && c.mode == ConstraintMode.hard).map((c) => c.name).join(', ')}.',
        );
      }
      final debts = state.debts
          .map((d) => d.copyWith(balance: d.nextBalance))
          .toList();
      if (state.debts.any((d) => d.paymentDue < d.interest)) {
        warnings.add(
          'Year $year: scheduled debt payments do not cover all accrued interest; unpaid interest is added to the balance.',
        );
      }
      result.add(
        YearProjection(
          year: year,
          plan: annualPlan,
          financial: financial,
          endingDebt: debts.fold(0.0, (sum, d) => sum + d.balance),
          rotationChanges: changes,
          feasible: report.feasible && rotationFeasible,
        ),
      );
      final inflation = 1 + state.settings.expenseInflationRate;
      state = state.copyWith(
        fields: state.fields
            .map(
              (f) => f.copyWith(
                currentCropId: allocation[f.id],
                cropHistory: [allocation[f.id]!, ...f.cropHistory],
              ),
            )
            .toList(),
        crops: state.crops
            .map(
              (c) => c.copyWith(
                pricePerUnit:
                    c.pricePerUnit * (1 + state.settings.priceGrowthRate),
                seedCostPerAcre: c.seedCostPerAcre * inflation,
                fertilizerCostPerAcre: c.fertilizerCostPerAcre * inflation,
                chemicalCostPerAcre: c.chemicalCostPerAcre * inflation,
                waterCostPerAcre: c.waterCostPerAcre * inflation,
                laborCostPerAcre: c.laborCostPerAcre * inflation,
                fuelCostPerAcre: c.fuelCostPerAcre * inflation,
                equipmentCostPerAcre: c.equipmentCostPerAcre * inflation,
              ),
            )
            .toList(),
        expenses: state.expenses
            .map(
              (e) => e.copyWith(
                annualAmount: e.annualAmount * (1 + e.inflationRate),
              ),
            )
            .toList(),
        debts: debts,
      );
    }
    return MultiYearProjection(years: result, warnings: warnings.toList());
  }

  MultiYearComparison compare(
    Farm farm,
    FarmPlan current,
    FarmPlan alternative, {
    int years = 5,
  }) => MultiYearComparison(
    current: project(farm, current, years: years),
    alternative: project(farm, alternative, years: years),
  );
}
