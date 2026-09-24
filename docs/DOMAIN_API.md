# FarmTwin domain API

Import `package:farmtwin/domain/farm_domain.dart`. Pure Dart; synchronous engines are intended to run inside `Isolate.run`/Flutter `compute`. No package dependencies. Invalid domain input throws `ValidationFailure`; missing data throws `DataUnavailableFailure`; unsupported sizes return/throw typed `OptimizationFailure` or `SimulationFailure`.

All stored models expose `toJson()`, `fromJson(Map<String,dynamic>)`, and `copyWith(...)`. Collections are immutable. Financial amounts are in the user's selected currency; acreage in acres, water in acre-feet, nitrogen in pounds, yield and price in the crop's `yieldUnit`.

## Input models

- `Farm(id, name, fields: List<Field>, crops: List<CropProfile>, expenses: List<Expense>, debts: List<Debt>, constraints: List<FarmConstraint>, settings: FarmSettings, provenance: Provenance, scenarios: List<StressScenario> = [], schemaVersion = 1)`; getters `acreage`, `currentPlan`; `crop(id)`, `field(id)`, `validate({bool requireReady = false})`.
- `Field(id, name, acres, currentCropId, compatibleCropIds: List<String>, cropHistory: List<String> = [], irrigated = true, soilType = '', yieldMultiplier = 1, provenance)`; `isCompatibleWith(CropProfile)` requires explicit ID membership and satisfied irrigation requirements. The field form explicitly initializes irrigation to false and both assignment/compatibility to empty; the model constructor default is not used as a farmer input.
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

Crop references use IDs, never display names. `Farm.validate()` requires every nonempty current crop to exist and be compatible; an empty current ID may persist as incomplete input. `validate(requireReady: true)` and `validatePlan()` reject incomplete assignments before calculation. Legacy reference normalization and the read-only editing path are documented in [CROP_COMPATIBILITY.md](CROP_COMPATIBILITY.md).

## Engines and outputs

- `FinancialEngine().evaluate(Farm, FarmPlan)` -> `FarmFinancialResult`: `revenue`, `variableExpense`, `fixedExpense`, `operatingExpense`, `contributionMargin`, `operatingIncome`, `debtService`, `cashAfterDebt`, `marginPerAcre`, nullable `debtCoverage`, `waterUsage`, `nitrogenUsage`, `concentration`, `diversity`, `soilCoverShare`, `costBreakdown: Map<String,double>`, `fields: List<FieldFinancialResult>`. Field results: `fieldId`, `cropId`, `acres`, `revenue`, `cost`, `contributionMargin`, `waterUsage`, `nitrogenUsage`, nullable `breakEvenPrice`, `breakEvenYield`.
- `ConstraintEngine().evaluate(farm,plan,financial)` -> `ConstraintReport`: `feasible`, `satisfied`, `total`, `alignment`, `checks: List<ConstraintCheck>` (`constraintId`, `name`, `kind`, `mode`, `actual`, `limit`, `satisfied`, `utilization: double?`).
- `OptimizationEngine().run(farm,{void Function(OptimizationProgress)? onProgress})` -> `OptimizationResult`: `current: EvaluatedPlan`, nullable `recommended: EvaluatedPlan`, `pareto: List<EvaluatedPlan>`, `representatives: Map<String,EvaluatedPlan>`, `diagnostics`, `warnings`. `EvaluatedPlan`: `plan`, `financial`, `constraints`, `objectives: Map<Objective,double>`, `score`. Diagnostics: `searchSpace` (String exact integer), `candidatesGenerated`, `candidatesPruned`, `plansEvaluated`, `feasiblePlans`, `paretoPlans`, `elapsedMicroseconds`, `approximate`, `strategy`. `OptimizationProgress` carries generated/evaluated/feasible actual counts. Results expose `toJson` summaries.
- `MonteCarloEngine().run(farm,plan,{SimulationConfig? config,void Function(int,int)? onProgress})` -> `MonteCarloResult`: `mean`, `median`, `standardDeviation`, `p05`, `p25`, `p75`, `p95`, `positiveCashProbability`, `negativeCashProbability`, `samples: List<double>`, `histogram({int bins = 20})` returning `List<HistogramBin>` (`lower`, `upper`, `count`), `iterations`, `seed`, `elapsedMicroseconds`. `toJson()` omits raw samples by default; `toJson(includeSamples:true)` includes them.
- `ScenarioEngine().apply(farm,scenario)` -> independent modified Farm; does not mutate input.
- `MultiYearEngine().project(farm,plan,{int years = 5})` -> `MultiYearProjection`: `years: List<YearProjection>` (`year`, `plan`, `financial`, `endingDebt`, `rotationChanges`, `feasible`), `cumulativeCash`, `warnings`. Rotations follow history and minimumRotationYears when enabled; debt amortizes each year and unpaid interest capitalizes. `compare(farm,current,alternative,{years=5})` -> `MultiYearComparison` (`current`, `alternative`, `firstYearDifference`, `cumulativeDifference`, `shortTermProfitTrap`).
- `AlertEngine().evaluate(farm,financial,report)` -> `List<FarmAlert>` (`id`, `severity: AlertSeverity`, `message`, `sourceValues: Map<String,double>`).
- `LocalExplanationEngine().explain(String question,Farm farm,{OptimizationResult? optimization,MonteCarloResult? risk})` -> dynamic String assembled only from current engine values, relevant field changes and constraints. It calculates the current farm when no run is supplied.

Domain test inputs live in `test/fixtures/farm.json` and are not packaged in the application. Every output is calculated at runtime. JSON fields mirror the constructor names above; enums serialize by `.name`.

## Computational limits and modeling disclosures

Algorithm safety controls are centralized beside the schema constants in `farm_models.dart`: at most 512 optimization fields, 2,048 crop profiles, 250,000 retained field evaluations and a 20,000,000 candidate/frontier comparison budget. The effective candidate budget is the minimum of the user setting and both work ceilings. If either ceiling changes the search, results explicitly report the bounded strategy and actual counts; warnings disclose the effective budget. Unsupported model dimensions throw `OptimizationFailure`. Monte Carlo rejects work exceeding 20,000,000 field-plus-crop factor draws with `SimulationFailure`; iteration limits remain 2–100,000. These are computation controls, never business assumptions.

`OptimizationEngine.evaluate(farm, plan)` additionally exposes a validated single-plan evaluation. `validate:false` is reserved for engine-internal prevalidated iterations. Crop lookup and acreage are cached inside each immutable Farm aggregate.

`LocalExplanationEngine.context/explain` accepts an optional `selected: EvaluatedPlan`; this overrides the run recommendation so explanations follow the user-selected plan. Uncalculated what-if requests direct users to Scenario lab.

Monte Carlo uses mean-corrected lognormal factors. Weather and market correlations are correlations of the underlying normal factors; output Pearson correlations need not be identical. All crop price factors and field yield factors are drawn in fixed model order before assignments are inspected, supporting common random numbers for paired plans. A crop's market shock is shared by every field growing that crop. The analytical resilience proxy likewise aggregates market exposure by crop. It does not include all simulated cost risks and is not a Monte Carlo percentile.

Water availability is modeled around the tightest enabled water cap, or current demand if no cap exists. A shortage proportionally reduces yields of crops with positive water requirements. This is an explicit simplified response curve, not a calibrated agronomic crop-water model. Break-even metrics include acreage-allocated fixed expenses and exclude debt/taxes. Five-year projections preserve the supplied first-year plan, then select highest-margin rotation-compatible replacements as needed; all annual hard constraints are checked and infeasible years are visibly reported. The projection is not a global multi-year optimization.
