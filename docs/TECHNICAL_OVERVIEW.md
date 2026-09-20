# Technical model definitions

## Financial model

Field revenue = acreage × crop yield per acre × field yield multiplier × price per yield unit. Variable expenses sum seven explicit per-acre cost categories. Farm operating income is revenue less variable and fixed expenses. Cash after debt subtracts annual debt service. Debt service is capped by principal plus accrued interest; unpaid interest increases the following year's balance.

Break-even yield and price allocate fixed expense proportionally by acreage. They exclude debt payments and unmodeled taxes, subsidies, insurance, and capital purchases. Undefined ratios return null rather than infinity. All inputs are validated for finiteness, ranges, references, uniqueness, and plan compatibility.

## Constraints and scoring

Water, nitrogen, operating expense, income, crop concentration/diversity, rotation, restricted inputs, liquidity, debt coverage/exposure, and soil cover are supplied data. Hard rules reject a plan. Preferences contribute to the fraction of configured requirements satisfied. Disabled rules are excluded. There is no universal ethics, sustainability, quality, or health score.

Objectives are normalized over the actual feasible candidate population before applying supplied weights. Positive weights total one. Objectives maximize operating income, cash minus an analytical risk proxy, negative water demand, negative nitrogen demand, practice alignment, and one minus crop concentration. Only objectives with positive weights participate in Pareto dominance. Equal outcome vectors collapse to a representative allocation.

Small spaces use exhaustive enumeration. Larger spaces use deterministic seeded exploration of global allocations and mutations of feasible or per-field extreme seed plans. This is not a proof of global optimality. A configured frontier limit bounds stored tradeoffs; warnings disclose approximation. Counters measure actual visited, rejected, evaluated, and feasible assignments; rejected candidates can also have financial evaluation, so those categories overlap. Runtime comes from a stopwatch.

Computational ceilings currently support 512 fields and 2,048 crop profiles. Retained financial rows and candidate/frontier comparison budgets can reduce the effective candidate limit below the user's requested limit; diagnostics disclose the effective budget and approximation. Oversized field/crop inputs and simulation workloads return typed failures. These are computational limits, not farm assumptions.

## Simulation

Yield, price, fertilizer, fuel, and water factors use mean-corrected lognormal multipliers parameterized by coefficients of variation. Shared normal weather and market factors introduce dependence. The configured correlations describe the latent normal shocks; transformed lognormal Pearson correlations can differ. All crop market draws and field yield draws are generated in stable order before the allocation is inspected, so paired plans consume comparable randomness. Fields with the same crop share the crop price shock.

Available water is centered on the tightest enabled annual water constraint, or modeled baseline water demand when no limit is supplied. Shortages proportionally reduce the yields of crops that use water. This simplified response is an explicit modeling assumption, not a calibrated agronomic response curve. Equipment failures subtract the supplied loss with the supplied annual probability.

Cash samples produce actual mean, interpolated quantiles, population standard deviation, positive/negative cash frequencies, and histogram counts. Zero cash is neither positive nor negative. Results are reproducible for the same inputs, seed, runtime/algorithm version. Saved records retain input snapshots and seeds; raw simulation draws and whole candidate populations stay local.

## Scenarios and five-year modeling

Scenarios transform input profiles, expense/debt assumptions, and water limits without mutating the base farm. Presets exist only as editable sample input data. Neutral multipliers are one and additions zero.

The multi-year engine advances crop history, price growth, variable/fixed expense inflation, and debt amortization. Rotation replacements are selected by a deterministic greedy rule. Every year's hard constraints are rechecked. Warnings disclose failed years and no global multi-year optimum is claimed. A short-term profit trap is reported only when the selected plan has positive Year 1 cash difference and negative cumulative cash difference under this model.

## Explanation and provenance

Local explanations classify supported intents and assemble language from current financial, constraint, selected allocation, and simulation results. Cloud explanation is optional and opt-in. The proxy permits metric references and rejects unsupported numerical claims before substituting actual supplied metrics. Cloud prose is not an engine and cannot establish that a farm input was verified.

Important model entities carry input source and timestamps, with optional provider, effective/retrieval dates, and quality metadata. Imported data is relabeled imported and cannot claim verification. There are no live market/weather integrations in this build; users enter or import assumptions explicitly.

## Persistence

The farm is an atomically written aggregate in `farms/{id}.data`, keeping constraints and references coherent. Scenarios may be part of the aggregate; saved runs and harvest batches are separate versioned entities. Native Firestore persistence provides cached data and queued writes; the UI reports cache/pending/failure metadata. Browser persistence is memory-only for cloud records in this build. The local Sample Farm is persisted through SharedPreferences and clearly labeled. See [DATA_MODEL.md](DATA_MODEL.md).
