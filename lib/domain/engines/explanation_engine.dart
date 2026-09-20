import '../models/farm_models.dart';
import '../models/results.dart';
import 'financial_engine.dart';
import 'constraint_engine.dart';

class AlertEngine {
  const AlertEngine();
  List<FarmAlert> evaluate(
    Farm farm,
    FarmFinancialResult financial,
    ConstraintReport report,
  ) {
    final alerts = <FarmAlert>[];
    for (final check in report.checks) {
      if (!check.satisfied) {
        alerts.add(
          FarmAlert(
            id: 'constraint-${check.constraintId}',
            severity: check.mode == ConstraintMode.hard
                ? AlertSeverity.critical
                : AlertSeverity.warning,
            message:
                '${check.name} is not satisfied: actual ${check.actual.toStringAsFixed(2)}, required limit ${check.limit.toStringAsFixed(2)}.',
            sourceValues: {'actual': check.actual, 'limit': check.limit},
          ),
        );
      } else if (check.utilization != null &&
          check.utilization! >= farm.settings.alertUtilizationThreshold) {
        alerts.add(
          FarmAlert(
            id: 'utilization-${check.constraintId}',
            severity: AlertSeverity.warning,
            message:
                '${check.name} uses ${(check.utilization! * 100).toStringAsFixed(1)}% of its limit.',
            sourceValues: {
              'actual': check.actual,
              'limit': check.limit,
              'utilization': check.utilization!,
              'alertThreshold': farm.settings.alertUtilizationThreshold,
            },
          ),
        );
      }
    }
    if (financial.cashAfterDebt < 0) {
      alerts.add(
        FarmAlert(
          id: 'negative-cash',
          severity: AlertSeverity.critical,
          message:
              'Expected annual cash after debt is negative (${financial.cashAfterDebt.toStringAsFixed(2)} ${farm.settings.currencyCode}).',
          sourceValues: {
            'cashAfterDebt': financial.cashAfterDebt,
            'operatingIncome': financial.operatingIncome,
            'debtService': financial.debtService,
          },
        ),
      );
    }
    for (final debt in farm.debts.where((d) => d.paymentDue < d.interest)) {
      alerts.add(
        FarmAlert(
          id: 'debt-${debt.id}',
          severity: AlertSeverity.warning,
          message:
              '${debt.name}: scheduled payment does not cover accrued interest.',
          sourceValues: {
            'payment': debt.paymentDue,
            'interest': debt.interest,
            'endingBalance': debt.nextBalance,
          },
        ),
      );
    }
    return List.unmodifiable(alerts);
  }
}

enum ExplanationIntent { fieldChange, constraints, risk, finance, summary }

class ExplanationContext {
  final ExplanationIntent intent;
  final Farm farm;
  final FarmFinancialResult current;
  final ConstraintReport currentConstraints;
  final EvaluatedPlan? alternative;
  final OptimizationResult? optimization;
  final MonteCarloResult? risk;
  final List<String> selectedFieldIds;
  ExplanationContext({
    required this.intent,
    required this.farm,
    required this.current,
    required this.currentConstraints,
    required this.alternative,
    required this.optimization,
    required this.risk,
    required List<String> selectedFieldIds,
  }) : selectedFieldIds = List.unmodifiable(selectedFieldIds);
}

class LocalExplanationEngine {
  const LocalExplanationEngine();
  ExplanationContext context(
    String question,
    Farm farm, {
    OptimizationResult? optimization,
    MonteCarloResult? risk,
    EvaluatedPlan? selected,
  }) {
    final normalized = question.toLowerCase();
    final fields = farm.fields
        .where((f) => normalized.contains(f.name.toLowerCase()))
        .map((f) => f.id)
        .toList();
    final intent =
        fields.isNotEmpty ||
            RegExp(r'\b(field|change|allocation|crop)\b').hasMatch(normalized)
        ? ExplanationIntent.fieldChange
        : RegExp(
            r'\b(risk|simulation|monte|percentile|downside|probability)\b',
          ).hasMatch(normalized)
        ? ExplanationIntent.risk
        : RegExp(
            r'\b(constraint|limit|water|nitrogen|binding|practice)\b',
          ).hasMatch(normalized)
        ? ExplanationIntent.constraints
        : RegExp(
            r'\b(profit|income|cash|debt|expense|cost|revenue)\b',
          ).hasMatch(normalized)
        ? ExplanationIntent.finance
        : ExplanationIntent.summary;
    final current = const FinancialEngine().evaluate(farm, farm.currentPlan);
    return ExplanationContext(
      intent: intent,
      farm: farm,
      current: current,
      currentConstraints: const ConstraintEngine().evaluate(
        farm,
        farm.currentPlan,
        current,
      ),
      alternative: selected ?? optimization?.recommended,
      optimization: optimization,
      risk: risk,
      selectedFieldIds: fields,
    );
  }

  String explain(
    String question,
    Farm farm, {
    OptimizationResult? optimization,
    MonteCarloResult? risk,
    EvaluatedPlan? selected,
  }) {
    if (RegExp(
      r'\b(what if|increase|decrease|scenario|another|happens if)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return 'Apply the requested assumptions in Scenario lab and run its optimizer to calculate that change. This explanation uses existing results and cannot infer an uncalculated scenario.';
    }
    return render(
      context(
        question,
        farm,
        optimization: optimization,
        risk: risk,
        selected: selected,
      ),
    );
  }

  String render(ExplanationContext context) {
    final farm = context.farm;
    final currency = farm.settings.currencyCode;
    String money(double value) => '${value.toStringAsFixed(2)} $currency';
    final current = context.current, alternative = context.alternative;
    final paragraphs = <String>[];
    if (context.intent == ExplanationIntent.risk) {
      final risk = context.risk;
      if (risk == null) {
        return 'Run a simulation for this farm to explain its cash-flow distribution. The model uses your configured yield, price, weather, market, cost and equipment assumptions.';
      }
      paragraphs.add(
        'Across ${risk.iterations} simulated years (seed ${risk.seed}), mean cash after debt is ${money(risk.mean)} and median cash is ${money(risk.median)}. The 5th to 95th percentile interval is ${money(risk.p05)} to ${money(risk.p95)}.',
      );
      paragraphs.add(
        'Negative cash occurred in ${(risk.negativeCashProbability * 100).toStringAsFixed(1)}% of simulations; positive cash occurred in ${(risk.positiveCashProbability * 100).toStringAsFixed(1)}%. These are outcomes under the entered uncertainty assumptions, not a forecast or guarantee. Weather correlation is ${farm.settings.simulation.weatherCorrelation.toStringAsFixed(2)} and market correlation is ${farm.settings.simulation.marketCorrelation.toStringAsFixed(2)}.',
      );
    } else if (context.intent == ExplanationIntent.fieldChange) {
      if (alternative == null) {
        return 'Run optimization to compare field assignments with the current plan. This farm currently assigns ${farm.fields.length} fields across ${current.diversity} crops.';
      }
      final selected = context.selectedFieldIds.isEmpty
          ? farm.fields
          : farm.fields.where((f) => context.selectedFieldIds.contains(f.id));
      for (final field in selected) {
        final before = current.fields.firstWhere((r) => r.fieldId == field.id);
        final after = alternative.financial.fields.firstWhere(
          (r) => r.fieldId == field.id,
        );
        final from = farm.crop(before.cropId), to = farm.crop(after.cropId);
        if (from.id == to.id) {
          paragraphs.add(
            '${field.name} keeps ${from.name}; its modeled contribution margin is ${money(after.contributionMargin)} and water requirement is ${after.waterUsage.toStringAsFixed(2)} acre-feet.',
          );
        } else {
          paragraphs.add(
            '${field.name} changes from ${from.name} to ${to.name}. Its annual contribution margin changes by ${money(after.contributionMargin - before.contributionMargin)}, and water requirements change by ${(after.waterUsage - before.waterUsage).toStringAsFixed(2)} acre-feet. This assignment is part of the farm-wide plan selected by your objective weights and hard constraints.',
          );
        }
      }
      paragraphs.add(
        'The selected plan satisfies ${alternative.constraints.satisfied} of ${alternative.constraints.total} enabled practice requirements. A field-level margin comparison does not establish which constraint caused the assignment; that requires a separate re-optimization with that constraint changed.',
      );
    } else if (context.intent == ExplanationIntent.constraints) {
      final report = alternative?.constraints ?? context.currentConstraints;
      if (report.total == 0) {
        return 'This farm has no enabled practice constraints. Add limits or preferences to define what an acceptable operating plan must satisfy.';
      }
      paragraphs.add(
        '${report.satisfied} of ${report.total} enabled requirements are satisfied for ${alternative == null ? 'the current' : 'the selected'} plan. Hard-constraint feasibility is ${report.feasible ? 'satisfied' : 'not satisfied'}.',
      );
      for (final check in report.checks) {
        paragraphs.add(
          '${check.name}: ${check.actual.toStringAsFixed(2)} against ${check.limit.toStringAsFixed(2)} (${check.mode.name}; ${check.satisfied ? 'satisfied' : 'not satisfied'}).${check.utilization == null ? '' : ' Limit utilization: ${(check.utilization! * 100).toStringAsFixed(1)}%.'}',
        );
      }
    } else {
      paragraphs.add(
        '${farm.name} models ${farm.acreage.toStringAsFixed(1)} acres across ${farm.fields.length} fields. Current expected revenue is ${money(current.revenue)}, operating expense is ${money(current.operatingExpense)}, and cash after debt is ${money(current.cashAfterDebt)}.',
      );
      if (alternative != null) {
        paragraphs.add(
          'The selected feasible plan changes operating income by ${money(alternative.financial.operatingIncome - current.operatingIncome)} and annual water use by ${(alternative.financial.waterUsage - current.waterUsage).toStringAsFixed(2)} acre-feet. It has ${alternative.financial.diversity} crops and ${(alternative.financial.concentration * 100).toStringAsFixed(1)}% maximum crop concentration.',
        );
      } else if (context.optimization != null) {
        paragraphs.add(
          'No feasible alternative was found in this run. Review its hard constraints and search diagnostics.',
        );
      }
      if (context.optimization != null) {
        final diagnostics = context.optimization!.diagnostics;
        paragraphs.add(
          'The ${diagnostics.strategy} run generated ${diagnostics.candidatesGenerated} candidates and found ${diagnostics.feasiblePlans} feasible plans.${diagnostics.approximate ? ' The search or displayed frontier is approximate; a global optimum is not guaranteed.' : ''}',
        );
      }
    }
    paragraphs.add(
      'Source: local calculations using the current farm assumptions. Scenario questions require applying the scenario and running the engines; no uncalculated changes are inferred.',
    );
    return paragraphs.join('\n\n');
  }
}
