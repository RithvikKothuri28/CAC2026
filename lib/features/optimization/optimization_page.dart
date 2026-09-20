import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../domain/farm_domain.dart';
import '../../app/theme/farm_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/charts.dart';
import '../farm/farm_editors.dart';
import '../workspace/workspace_controller.dart';

class OptimizationPage extends StatelessWidget {
  const OptimizationPage({super.key, required this.state});
  final WorkspaceController state;
  @override
  Widget build(BuildContext context) {
    if (!state.ready) {
      return EmptyState(
        icon: Icons.auto_graph,
        title: 'Define your farm first',
        message:
            'Add fields and crop options to generate feasible operating plans.',
        action: FilledButton(
          onPressed: () => context.go('/farm'),
          child: const Text('Set up farm'),
        ),
      );
    }
    final farm = state.farm!;
    final run = state.optimization;
    final chosen = state.selected;
    final cc = farm.settings.currencyCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Find your room to grow.',
          'Your boundaries. Calculated alternatives. Your decision.',
          action: FilledButton.icon(
            onPressed: state.busy ? null : state.optimize,
            icon: const Icon(Icons.auto_graph),
            label: Text(run == null ? 'Run optimization' : 'Re-optimize'),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: state.busy ? null : () => context.go('/farm?tab=2'),
              icon: const Icon(Icons.rule),
              label: const Text('Edit constraints'),
            ),
            OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : () => editFarmSettings(context, state),
              icon: const Icon(Icons.tune),
              label: const Text('Objective weights'),
            ),
            if (run != null)
              OutlinedButton.icon(
                onPressed: state.busy ? null : () => state.saveRun(false),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save run'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (run == null)
          SectionCard(
            title: 'Explore the feasible plans',
            subtitle:
                '${farm.fields.length} fields · ${farm.crops.length} crop profiles · ${farm.constraints.where((c) => c.mode == ConstraintMode.hard).length} hard constraints',
            child: const Text(
              'FarmTwin evaluates crop assignments, rejects plans that violate hard limits, and compares the remaining plans across normalized objectives. The search runs on your device. Large searches report their limits.',
            ),
          ),
        if (run != null) ...[
          ResponsiveGrid(
            minWidth: 150,
            children: [
              Metric(
                label: 'GENERATED',
                value: number(run.diagnostics.candidatesGenerated),
                icon: Icons.grid_view,
                note: 'Actual candidate assignments',
              ),
              Metric(
                label: 'PRUNED',
                value: number(run.diagnostics.candidatesPruned),
                icon: Icons.filter_alt_outlined,
                note: 'Incompatible or invalid',
              ),
              Metric(
                label: 'EVALUATED',
                value: number(run.diagnostics.plansEvaluated),
                icon: Icons.calculate_outlined,
                note: 'Financial plans calculated',
              ),
              Metric(
                label: 'FEASIBLE',
                value: number(run.diagnostics.feasiblePlans),
                icon: Icons.check_circle_outline,
                note: 'Pass all hard constraints',
              ),
              Metric(
                label: 'PARETO PLANS',
                value: number(run.diagnostics.paretoPlans),
                icon: Icons.scatter_plot_outlined,
                note:
                    '${number(run.diagnostics.elapsedMicroseconds / 1000)} ms runtime',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${run.diagnostics.strategy} · Compatible search space: ${run.diagnostics.searchSpace} · ${run.diagnostics.approximate ? 'Approximate search' : 'Exhaustive search'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final warning in run.warnings) ...[
            const SizedBox(height: 12),
            Notice(warning),
          ],
          const SizedBox(height: 24),
          if (run.recommended == null)
            const Notice(
              'No feasible plan was found. Review incompatible fields and hard limits before running again.',
              error: true,
            ),
          if (run.pareto.isNotEmpty)
            SectionCard(
              title: 'Tradeoff explorer',
              subtitle:
                  'Tap an efficient alternative. The chart shows water and income; dominance uses all active objectives.',
              child: TradeoffChart(
                plans: run.pareto,
                current: run.current,
                selected: chosen,
                onSelect: state.selectPlan,
              ),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: run.representatives.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(entry.key),
                    selected: chosen == entry.value,
                    onSelected: (_) => state.selectPlan(entry.value),
                  ),
                )
                .toList(),
          ),
          if (chosen != null) ...[
            const SizedBox(height: 24),
            SectionCard(
              title: 'Current vs selected plan',
              subtitle: 'Calculated annual outlook · $cc',
              child: comparisonTable(
                context,
                run.current.financial,
                chosen.financial,
                cc,
              ),
            ),
            const SizedBox(height: 24),
            SectionCard(
              title: 'The proposed allocation',
              subtitle:
                  '${chosen.constraints.satisfied} / ${chosen.constraints.total} practice requirements satisfied',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FarmCanvas(farm: farm, plan: chosen.plan),
                  const SizedBox(height: 20),
                  ...farm.fields.map((field) {
                    final next = chosen.plan.assignments[field.id]!;
                    final changed = next != field.currentCropId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Expanded(child: Text(field.name)),
                          Flexible(
                            child: Text(
                              '${farm.crop(field.currentCropId).name} ${changed ? '→ ${farm.crop(next).name}' : '· unchanged'}',
                              style: TextStyle(
                                color: changed
                                    ? FarmTheme.forest
                                    : FarmTheme.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: state.busy
                            ? null
                            : () {
                                context.go('/risk');
                                state.simulate();
                              },
                        icon: const Icon(Icons.show_chart),
                        label: const Text('Compare risk'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () async {
                                if (await confirmAction(
                                  context,
                                  'Apply selected allocation?',
                                  'Update the current crop for each field to this plan. Existing calculated results will be cleared.',
                                )) {
                                  await state.perform(
                                    'Applying selected plan',
                                    state.applySelected,
                                  );
                                }
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Apply allocation'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

Widget comparisonTable(
  BuildContext context,
  FarmFinancialResult current,
  FarmFinancialResult selected,
  String cc,
) {
  final rows = <(String, double, double, bool)>[
    ('Revenue', current.revenue, selected.revenue, true),
    (
      'Operating expense',
      current.operatingExpense,
      selected.operatingExpense,
      true,
    ),
    (
      'Operating income',
      current.operatingIncome,
      selected.operatingIncome,
      true,
    ),
    ('Debt service', current.debtService, selected.debtService, true),
    ('Cash after debt', current.cashAfterDebt, selected.cashAfterDebt, true),
    ('Water (acre-ft)', current.waterUsage, selected.waterUsage, false),
    ('Nitrogen (lb)', current.nitrogenUsage, selected.nitrogenUsage, false),
  ];
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columnSpacing: 28,
      columns: const [
        DataColumn(label: Text('Metric')),
        DataColumn(label: Text('Current'), numeric: true),
        DataColumn(label: Text('Selected'), numeric: true),
        DataColumn(label: Text('Change'), numeric: true),
      ],
      rows: rows
          .map(
            (row) => DataRow(
              cells: [
                DataCell(Text(row.$1)),
                DataCell(Text(row.$4 ? currency(row.$2, cc) : number(row.$2))),
                DataCell(Text(row.$4 ? currency(row.$3, cc) : number(row.$3))),
                DataCell(
                  Text(
                    row.$4
                        ? currency(row.$3 - row.$2, cc)
                        : number(row.$3 - row.$2),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    ),
  );
}
