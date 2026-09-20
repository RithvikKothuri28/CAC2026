import '../models/farm_models.dart';

class ScenarioEngine {
  const ScenarioEngine();
  Farm apply(Farm farm, StressScenario scenario) {
    farm.validate();
    scenario.validate();
    final result = farm.copyWith(
      crops: farm.crops
          .map(
            (c) => c.copyWith(
              pricePerUnit: c.pricePerUnit * scenario.priceMultiplier,
              yieldPerAcre: c.yieldPerAcre * scenario.yieldMultiplier,
              fertilizerCostPerAcre:
                  c.fertilizerCostPerAcre * scenario.fertilizerMultiplier,
              fuelCostPerAcre: c.fuelCostPerAcre * scenario.fuelMultiplier,
              laborCostPerAcre: c.laborCostPerAcre * scenario.laborMultiplier,
            ),
          )
          .toList(),
      debts: farm.debts
          .map(
            (d) => d.copyWith(
              annualInterestRate:
                  d.annualInterestRate * scenario.interestRateMultiplier,
            ),
          )
          .toList(),
      constraints: farm.constraints
          .map(
            (c) => c.kind == ConstraintKind.maxWater
                ? c.copyWith(
                    limit: c.limit * scenario.waterAvailabilityMultiplier,
                  )
                : c,
          )
          .toList(),
      expenses: [
        ...farm.expenses,
        if (scenario.equipmentCostAddition > 0)
          Expense(
            id: 'scenario-equipment-${scenario.id}',
            name: '${scenario.name}: additional equipment expense',
            annualAmount: scenario.equipmentCostAddition,
            inflationRate: 0,
            provenance: farm.provenance,
          ),
      ],
    );
    result.validate();
    return result;
  }
}
