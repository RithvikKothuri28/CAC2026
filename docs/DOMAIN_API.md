# FarmTwin domain API

Import `package:farmtwin/domain/farm_domain.dart`. Pure Dart; synchronous engines are intended to run inside `Isolate.run`/Flutter `compute`. No package dependencies. Invalid domain input throws `ValidationFailure`; missing data throws `DataUnavailableFailure`; unsupported sizes return/throw typed `OptimizationFailure` or `SimulationFailure`.

All stored models expose `toJson()`, `fromJson(Map<String,dynamic>)`, and `copyWith(...)`. Collections are immutable. Financial amounts are in the user's selected currency; acreage in acres, water in acre-feet, nitrogen in pounds, yield and price in the crop's `yieldUnit`.

## Input models

- `Farm(id, name, fields: List<Field>, crops: List<CropProfile>, expenses: List<Expense>, debts: List<Debt>, constraints: List<FarmConstraint>, settings: FarmSettings, provenance: Provenance, scenarios: List<StressScenario> = [], schemaVersion = 1)`; getters `acreage`, `currentPlan`; `crop(id)`, `field(id)`, `validate({bool requireReady = false})`.
- `Field(id, name, acres, currentCropId, compatibleCropIds: List<String>, cropHistory: List<String> = [], irrigated = true, soilType = '', yieldMultiplier = 1, provenance)`.
- `CropProfile(id, name, yieldPerAcre, pricePerUnit, yieldUnit, seedCostPerAcre, fertilizerCostPerAcre, chemicalCostPerAcre, waterCostPerAcre, laborCostPerAcre, fuelCostPerAcre, equipmentCostPerAcre, waterPerAcre, nitrogenPerAcre, yieldVolatility, priceVolatility, rotationFamily, minimumRotationYears, requiresIrrigation, inputs: List<String>, providesSoilCover, provenance)`; getter `costPerAcre`.
- `Expense(id, name, annualAmount, inflationRate, provenance)`.
- `Debt(id, name, balance, annualInterestRate, annualPayment, provenance)`.
- `FarmConstraint(id, name, kind: ConstraintKind, mode: ConstraintMode, limit: double, restrictedInputs: List<String> = [])`.
- `ConstraintKind`: `maxWater`, `maxNitrogen`, `maxOperatingExpense`, `minOperatingIncome`, `maxConcentration`, `minDiversity`, `rotation`, `restrictedInputs`, `minLiquidity`, `minDebtCoverage`, `minSoilCover`, `maxDebt`.
- `ConstraintMode`: `hard`, `preference`, `disabled`.
- `Objective`: `profit`, `resilience`, `waterEfficiency`, `inputEfficiency`, `practiceAlignment`, `diversification`.
- `OptimizationConfig(weights: Map<Objective,double>, exhaustiveLimit, candidateLimit, frontierLimit, seed)`; positive weights must total 1; capacity limits are computational controls.
- `SimulationConfig(iterations, seed, weatherCorrelation, marketCorrelation, fertilizerVolatility, fuelVolatility, waterVolatility, equipmentFailureProbability, equipmentFailureCost)`; correlation is intra-factor nonnegative [0,1]. Shared weather shocks correlate field yields; shared market shocks correlate crop prices.
- `FarmSettings(currencyCode, optimization: OptimizationConfig, simulation: SimulationConfig, priceGrowthRate, expenseInflationRate, liquidityReserve, alertUtilizationThreshold)`.
- `DataSourceType`: `userEntered`, `imported`, `externalProvider`, `configuredDefault`, `sample`.
- `Provenance(source, updatedAt: DateTime, provider: String?, retrievedAt: DateTime?, effectiveDate: DateTime?, quality: String?)`.
- `FarmPlan(assignments: Map<String,String>)` maps field id to crop id; `toJson/fromJson`, `copyWith`.
- `StressScenario(id, name, priceMultiplier, yieldMultiplier, fertilizerMultiplier, fuelMultiplier, laborMultiplier, waterAvailabilityMultiplier, interestRateMultiplier, equipmentCostAddition)`; neutral multiplier defaults are 1, addition 0.

## Engines and outputs

- `FinancialEngine().evaluate(Farm, FarmPlan)` -> `FarmFinancialResult`: `revenue`, `variableExpense`, `fixedExpense`, `operatingExpense`, `contributionMargin`, `operatingIncome`, `debtService`, `cashAfterDebt`, `marginPerAcre`, nullable `debtCoverage`, `waterUsage`, `nitrogenUsage`, `concentration`, `diversity`, `soilCoverShare`, `costBreakdown: Map<String,double>`, `fields: List<FieldFinancialResult>`. Field results: `fieldId`, `cropId`, `acres`, `revenue`, `cost`, `contributionMargin`, `waterUsage`, `nitrogenUsage`, nullable `breakEvenPrice`, `breakEvenYield`.
- `ConstraintEngine().evaluate(farm,plan,financial)` -> `ConstraintReport`: `feasible`, `satisfied`, `total`, `alignment`, `checks: List<ConstraintCheck>` (`constraintId`, `name`, `kind`, `mode`, `actual`, `limit`, `satisfied`, `utilization: double?`).
- `OptimizationEngine().run(farm,{void Function(OptimizationProgress)? onProgress})` -> `OptimizationResult`: `current: EvaluatedPlan`, nullable `recommended: EvaluatedPlan`, `pareto: List<EvaluatedPlan>`, `representatives: Map<String,EvaluatedPlan>`, `diagnostics`, `warnings`. `EvaluatedPlan`: `plan`, `financial`, `constraints`, `objectives: Map<Objective,double>`, `score`. Diagnostics: `searchSpace` (String exact integer), `candidatesGenerated`, `candidatesPruned`, `plansEvaluated`, `feasiblePlans`, `paretoPlans`, `elapsedMicroseconds`, `approximate`, `strategy`. `OptimizationProgress` carries generated/evaluated/feasible actual counts. Results expose `toJson` summaries.
- `MonteCarloEngine().run(farm,plan,{SimulationConfig? config,void Function(int,int)? onProgress})` -> `MonteCarloResult`: `mean`, `median`, `standardDeviation`, `p05`, `p25`, `p75`, `p95`, `positiveCashProbability`, `negativeCashProbability`, `samples: List<double>`, `histogram({int bins = 20})` returning `List<HistogramBin>` (`lower`, `upper`, `count`), `iterations`, `seed`, `elapsedMicroseconds`. `toJson()` omits raw samples by default; `toJson(includeSamples:true)` includes them.
- `ScenarioEngine().apply(farm,scenario)` -> independent modified Farm; does not mutate input.
- `MultiYearEngine().project(farm,plan,{int years = 5})` -> `MultiYearProjection`: `years: List<YearProjection>` (`year`, `plan`, `financial`, `endingDebt`, `rotationChanges`, `feasible`), `cumulativeCash`, `warnings`. Rotations follow history and minimumRotationYears when enabled; debt amortizes each year and unpaid interest capitalizes. `compare(farm,current,alternative,{years=5})` -> `MultiYearComparison` (`current`, `alternative`, `firstYearDifference`, `cumulativeDifference`, `shortTermProfitTrap`).
- `AlertEngine().evaluate(farm,financial,report)` -> `List<FarmAlert>` (`id`, `severity: AlertSeverity`, `message`, `sourceValues: Map<String,double>`).
- `LocalExplanationEngine().explain(String question,Farm farm,{OptimizationResult? optimization,MonteCarloResult? risk})` -> dynamic String assembled only from current engine values, relevant field changes and constraints. It calculates the current farm when no run is supplied.

The sample is input only: `assets/sample/sample_farm.json`. Every output is calculated at runtime. JSON fields mirror the constructor names above; enums serialize by `.name`.
