import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/components.dart';
import '../../domain/farm_domain.dart';
import '../farm/farm_editors.dart';
import '../workspace/workspace_controller.dart';

class RiskPage extends StatelessWidget {
  const RiskPage({super.key, required this.state});
  final WorkspaceController state;
  @override
  Widget build(BuildContext context) {
    if (!state.ready) {
      return EmptyState(
        icon: Icons.show_chart,
        title: 'Build a farm to model risk',
        message:
            'Risk simulations need fields, crop economics, and your uncertainty assumptions.',
        action: FilledButton(
          onPressed: () => context.go('/farm'),
          child: const Text('Set up farm'),
        ),
      );
    }
    final farm = state.farm!;
    final cc = farm.settings.currencyCode;
    final risk = state.risk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Look beyond the average.',
          'Understand how uncertainty changes your cash outlook.',
          action: FilledButton.icon(
            onPressed: state.busy ? null : state.simulate,
            icon: const Icon(Icons.show_chart),
            label: const Text('Run simulation'),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : () => editFarmSettings(context, state),
              icon: const Icon(Icons.tune),
              label: const Text('Simulation assumptions'),
            ),
            if (risk != null)
              OutlinedButton.icon(
                onPressed: state.busy ? null : () => state.saveRun(true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save simulation'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Notice(
          '${number(farm.settings.simulation.iterations)} iterations · seed ${farm.settings.simulation.seed}. '
          '${state.selected == null ? 'Run optimization and select a plan to compare it with the current farm.' : 'Both plans use the same seed for comparable modeled shocks.'}',
        ),
        const SizedBox(height: 24),
        if (risk != null) ...[
          ResponsiveGrid(
            children: [
              Metric(
                label: 'CURRENT MEAN CASH',
                value: currency(risk.current.mean, cc),
                icon: Icons.account_balance_wallet_outlined,
                negative: risk.current.mean < 0,
              ),
              Metric(
                label: 'CURRENT LOSS PROBABILITY',
                value: percentage(risk.current.negativeCashProbability),
                icon: Icons.south_east,
                note: 'Cash after debt below zero',
              ),
              Metric(
                label: 'SELECTED MEAN CASH',
                value: risk.alternative == null
                    ? '—'
                    : currency(risk.alternative!.mean, cc),
                icon: Icons.trending_up,
              ),
              Metric(
                label: 'SELECTED LOSS PROBABILITY',
                value: risk.alternative == null
                    ? '—'
                    : percentage(risk.alternative!.negativeCashProbability),
                icon: Icons.shield_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Cash flow distribution',
            subtitle:
                'Computed Monte Carlo samples · $cc · red line marks zero when within range',
            child: DistributionChart(
              current: risk.current,
              alternative: risk.alternative,
            ),
          ),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Risk statistics',
            subtitle:
                '${number(risk.current.elapsedMicroseconds / 1000)} ms current-plan simulation runtime',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Statistic')),
                  DataColumn(label: Text('Current'), numeric: true),
                  DataColumn(label: Text('Selected'), numeric: true),
                ],
                rows:
                    <(String, double Function(MonteCarloResult))>[
                          ('Mean', (r) => r.mean),
                          ('Median', (r) => r.median),
                          ('Standard deviation', (r) => r.standardDeviation),
                          ('5th percentile', (r) => r.p05),
                          ('25th percentile', (r) => r.p25),
                          ('75th percentile', (r) => r.p75),
                          ('95th percentile', (r) => r.p95),
                        ]
                        .map(
                          (row) => DataRow(
                            cells: [
                              DataCell(Text(row.$1)),
                              DataCell(
                                Text(currency(row.$2(risk.current), cc)),
                              ),
                              DataCell(
                                Text(
                                  risk.alternative == null
                                      ? '—'
                                      : currency(row.$2(risk.alternative!), cc),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
        ] else
          const SectionCard(
            title: 'Uncertainty, made visible',
            child: Text(
              'Simulations draw uncertain yields, prices, resource availability, fertilizer and fuel costs, and equipment failures from your assumptions. Probabilities describe this model; they are not observed historical frequencies.',
            ),
          ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Five-year perspective',
          subtitle:
              'Annual price and expense changes, rotation, and debt schedules',
          action: OutlinedButton(
            onPressed: state.busy ? null : state.project,
            child: const Text('Calculate'),
          ),
          child: state.projection == null
              ? const Text(
                  'Calculate how the current and selected allocations evolve. Review growth, inflation, and crop rotation assumptions in Model assumptions.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.selected == null)
                      const Notice(
                        'No alternative selected. Both columns project the current allocation.',
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Year')),
                          DataColumn(
                            label: Text('Current cash'),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text('Selected cash'),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text('Selected ending debt'),
                            numeric: true,
                          ),
                          DataColumn(label: Text('Feasible')),
                        ],
                        rows: List.generate(
                          state.projection!.current.years.length,
                          (index) {
                            final current =
                                state.projection!.current.years[index];
                            final alternative =
                                state.projection!.alternative.years[index];
                            return DataRow(
                              cells: [
                                DataCell(Text('${current.year}')),
                                DataCell(
                                  Text(
                                    currency(
                                      current.financial.cashAfterDebt,
                                      cc,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    currency(
                                      alternative.financial.cashAfterDebt,
                                      cc,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(currency(alternative.endingDebt, cc)),
                                ),
                                DataCell(
                                  Text(alternative.feasible ? 'Yes' : 'No'),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cumulative cash difference: ${currency(state.projection!.cumulativeDifference, cc)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (state.projection!.shortTermProfitTrap)
                      const Notice(
                        'The selected plan has higher Year 1 cash but lower cumulative cash. Review rotation changes and annual debt and expense assumptions.',
                        error: true,
                      ),
                    ...{
                      ...state.projection!.current.warnings,
                      ...state.projection!.alternative.warnings,
                    }.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Notice(warning),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
