import 'farm_models.dart';

class FieldFinancialResult {
  final String fieldId, cropId;
  final double acres, revenue, cost, waterUsage, nitrogenUsage;
  final double? breakEvenPrice, breakEvenYield;
  const FieldFinancialResult({
    required this.fieldId,
    required this.cropId,
    required this.acres,
    required this.revenue,
    required this.cost,
    required this.waterUsage,
    required this.nitrogenUsage,
    required this.breakEvenPrice,
    required this.breakEvenYield,
  });
  double get contributionMargin => revenue - cost;
  Map<String, dynamic> toJson() => {
    'fieldId': fieldId,
    'cropId': cropId,
    'acres': acres,
    'revenue': revenue,
    'cost': cost,
    'waterUsage': waterUsage,
    'nitrogenUsage': nitrogenUsage,
    'breakEvenPrice': breakEvenPrice,
    'breakEvenYield': breakEvenYield,
    'contributionMargin': contributionMargin,
  };
}

class FarmFinancialResult {
  final double revenue,
      variableExpense,
      fixedExpense,
      debtService,
      waterUsage,
      nitrogenUsage,
      concentration,
      soilCoverShare,
      acreage;
  final int diversity;
  final Map<String, double> costBreakdown;
  final List<FieldFinancialResult> fields;
  FarmFinancialResult({
    required this.revenue,
    required this.variableExpense,
    required this.fixedExpense,
    required this.debtService,
    required this.waterUsage,
    required this.nitrogenUsage,
    required this.concentration,
    required this.diversity,
    required this.soilCoverShare,
    required this.acreage,
    required Map<String, double> costBreakdown,
    required List<FieldFinancialResult> fields,
  }) : costBreakdown = Map.unmodifiable(costBreakdown),
       fields = List.unmodifiable(fields);
  double get operatingExpense => variableExpense + fixedExpense;
  double get contributionMargin => revenue - variableExpense;
  double get operatingIncome => revenue - operatingExpense;
  double get cashAfterDebt => operatingIncome - debtService;
  double get marginPerAcre => acreage == 0 ? 0 : operatingIncome / acreage;
  double? get debtCoverage =>
      debtService == 0 ? null : operatingIncome / debtService;
  Map<String, dynamic> toJson() => {
    'revenue': revenue,
    'variableExpense': variableExpense,
    'fixedExpense': fixedExpense,
    'operatingExpense': operatingExpense,
    'contributionMargin': contributionMargin,
    'operatingIncome': operatingIncome,
    'debtService': debtService,
    'cashAfterDebt': cashAfterDebt,
    'marginPerAcre': marginPerAcre,
    'debtCoverage': debtCoverage,
    'waterUsage': waterUsage,
    'nitrogenUsage': nitrogenUsage,
    'concentration': concentration,
    'diversity': diversity,
    'soilCoverShare': soilCoverShare,
    'acreage': acreage,
    'costBreakdown': costBreakdown,
    'fields': fields.map((f) => f.toJson()).toList(),
  };
}

class ConstraintCheck {
  final String constraintId, name;
  final ConstraintKind kind;
  final ConstraintMode mode;
  final double actual, limit;
  final bool satisfied;
  final double? utilization;
  const ConstraintCheck({
    required this.constraintId,
    required this.name,
    required this.kind,
    required this.mode,
    required this.actual,
    required this.limit,
    required this.satisfied,
    this.utilization,
  });
  Map<String, dynamic> toJson() => {
    'constraintId': constraintId,
    'name': name,
    'kind': kind.name,
    'mode': mode.name,
    'actual': actual,
    'limit': limit,
    'satisfied': satisfied,
    'utilization': utilization,
  };
}

class ConstraintReport {
  final List<ConstraintCheck> checks;
  ConstraintReport(List<ConstraintCheck> checks)
    : checks = List.unmodifiable(checks);
  bool get feasible =>
      checks.every((c) => c.mode != ConstraintMode.hard || c.satisfied);
  int get satisfied => checks.where((c) => c.satisfied).length;
  int get total => checks.length;
  double get alignment => total == 0 ? 1 : satisfied / total;
  Map<String, dynamic> toJson() => {
    'feasible': feasible,
    'satisfied': satisfied,
    'total': total,
    'alignment': alignment,
    'checks': checks.map((c) => c.toJson()).toList(),
  };
}

class EvaluatedPlan {
  final FarmPlan plan;
  final FarmFinancialResult financial;
  final ConstraintReport constraints;
  final Map<Objective, double> objectives;
  final double score;
  EvaluatedPlan({
    required this.plan,
    required this.financial,
    required this.constraints,
    required Map<Objective, double> objectives,
    this.score = 0,
  }) : objectives = Map.unmodifiable(objectives);
  EvaluatedPlan withScore(double score) => EvaluatedPlan(
    plan: plan,
    financial: financial,
    constraints: constraints,
    objectives: objectives,
    score: score,
  );
  Map<String, dynamic> toJson() => {
    'plan': plan.toJson(),
    'financial': financial.toJson(),
    'constraints': constraints.toJson(),
    'objectives': objectives.map((k, v) => MapEntry(k.name, v)),
    'score': score,
  };
}

class OptimizationProgress {
  final int generated, evaluated, feasible;
  const OptimizationProgress({
    required this.generated,
    required this.evaluated,
    required this.feasible,
  });
}

class OptimizationDiagnostics {
  final String searchSpace, strategy;
  final int candidatesGenerated,
      candidatesPruned,
      plansEvaluated,
      feasiblePlans,
      paretoPlans,
      elapsedMicroseconds;
  final bool approximate;
  const OptimizationDiagnostics({
    required this.searchSpace,
    required this.strategy,
    required this.candidatesGenerated,
    required this.candidatesPruned,
    required this.plansEvaluated,
    required this.feasiblePlans,
    required this.paretoPlans,
    required this.elapsedMicroseconds,
    required this.approximate,
  });
  Map<String, dynamic> toJson() => {
    'searchSpace': searchSpace,
    'strategy': strategy,
    'candidatesGenerated': candidatesGenerated,
    'candidatesPruned': candidatesPruned,
    'plansEvaluated': plansEvaluated,
    'feasiblePlans': feasiblePlans,
    'paretoPlans': paretoPlans,
    'elapsedMicroseconds': elapsedMicroseconds,
    'approximate': approximate,
  };
}

class OptimizationResult {
  final EvaluatedPlan current;
  final EvaluatedPlan? recommended;
  final List<EvaluatedPlan> pareto;
  final Map<String, EvaluatedPlan> representatives;
  final OptimizationDiagnostics diagnostics;
  final List<String> warnings;
  OptimizationResult({
    required this.current,
    required this.recommended,
    required List<EvaluatedPlan> pareto,
    required Map<String, EvaluatedPlan> representatives,
    required this.diagnostics,
    required List<String> warnings,
  }) : pareto = List.unmodifiable(pareto),
       representatives = Map.unmodifiable(representatives),
       warnings = List.unmodifiable(warnings);
  Map<String, dynamic> toJson() => {
    'current': current.toJson(),
    'recommended': recommended?.toJson(),
    'pareto': pareto.map((v) => v.toJson()).toList(),
    'representatives': representatives.map((k, v) => MapEntry(k, v.toJson())),
    'diagnostics': diagnostics.toJson(),
    'warnings': warnings,
  };
}

class HistogramBin {
  final double lower, upper;
  final int count;
  const HistogramBin({
    required this.lower,
    required this.upper,
    required this.count,
  });
}

class MonteCarloResult {
  final double mean,
      median,
      standardDeviation,
      p05,
      p25,
      p75,
      p95,
      positiveCashProbability,
      negativeCashProbability;
  final List<double> samples;
  final int iterations, seed, elapsedMicroseconds;
  MonteCarloResult({
    required this.mean,
    required this.median,
    required this.standardDeviation,
    required this.p05,
    required this.p25,
    required this.p75,
    required this.p95,
    required this.positiveCashProbability,
    required this.negativeCashProbability,
    required List<double> samples,
    required this.iterations,
    required this.seed,
    required this.elapsedMicroseconds,
  }) : samples = List.unmodifiable(samples);
  List<HistogramBin> histogram({int bins = 20}) {
    if (bins < 1 || bins > 1000) {
      throw const ValidationFailure(
        'Histogram bins must be between 1 and 1,000.',
      );
    }
    if (samples.isEmpty) return const [];
    final sorted = samples.toList()..sort();
    final lower = sorted.first, upper = sorted.last;
    if (lower == upper) {
      return [HistogramBin(lower: lower, upper: upper, count: samples.length)];
    }
    final width = (upper - lower) / bins;
    final counts = List<int>.filled(bins, 0);
    for (final x in sorted) {
      final i = ((x - lower) / width).floor().clamp(0, bins - 1);
      counts[i]++;
    }
    return List.generate(
      bins,
      (i) => HistogramBin(
        lower: lower + i * width,
        upper: lower + (i + 1) * width,
        count: counts[i],
      ),
    );
  }

  Map<String, dynamic> toJson({bool includeSamples = false}) => {
    'mean': mean,
    'median': median,
    'standardDeviation': standardDeviation,
    'p05': p05,
    'p25': p25,
    'p75': p75,
    'p95': p95,
    'positiveCashProbability': positiveCashProbability,
    'negativeCashProbability': negativeCashProbability,
    'iterations': iterations,
    'seed': seed,
    'elapsedMicroseconds': elapsedMicroseconds,
    if (includeSamples) 'samples': samples,
  };
}

class YearProjection {
  final int year;
  final FarmPlan plan;
  final FarmFinancialResult financial;
  final double endingDebt;
  final int rotationChanges;
  final bool feasible;
  const YearProjection({
    required this.year,
    required this.plan,
    required this.financial,
    required this.endingDebt,
    required this.rotationChanges,
    required this.feasible,
  });
  Map<String, dynamic> toJson() => {
    'year': year,
    'plan': plan.toJson(),
    'financial': financial.toJson(),
    'endingDebt': endingDebt,
    'rotationChanges': rotationChanges,
    'feasible': feasible,
  };
}

class MultiYearProjection {
  final List<YearProjection> years;
  final List<String> warnings;
  MultiYearProjection({
    required List<YearProjection> years,
    required List<String> warnings,
  }) : years = List.unmodifiable(years),
       warnings = List.unmodifiable(warnings);
  double get cumulativeCash =>
      years.fold(0.0, (sum, y) => sum + y.financial.cashAfterDebt);
  Map<String, dynamic> toJson() => {
    'years': years.map((y) => y.toJson()).toList(),
    'cumulativeCash': cumulativeCash,
    'warnings': warnings,
  };
}

class MultiYearComparison {
  final MultiYearProjection current, alternative;
  const MultiYearComparison({required this.current, required this.alternative});
  double get firstYearDifference =>
      alternative.years.first.financial.cashAfterDebt -
      current.years.first.financial.cashAfterDebt;
  double get cumulativeDifference =>
      alternative.cumulativeCash - current.cumulativeCash;
  bool get shortTermProfitTrap =>
      firstYearDifference > 0 && cumulativeDifference < 0;
}

class FarmAlert {
  final String id, message;
  final AlertSeverity severity;
  final Map<String, double> sourceValues;
  FarmAlert({
    required this.id,
    required this.message,
    required this.severity,
    required Map<String, double> sourceValues,
  }) : sourceValues = Map.unmodifiable(sourceValues);
}
