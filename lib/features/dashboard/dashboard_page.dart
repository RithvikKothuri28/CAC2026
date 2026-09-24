import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/farm_theme.dart';
import '../../domain/farm_domain.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/charts.dart';
import '../farm/farm_editors.dart';
import '../workspace/workspace_controller.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.state});
  final WorkspaceController state;
  @override
  Widget build(BuildContext context) {
    final farm = state.farm!;
    final result = state.financial;
    final cc = farm.settings.currencyCode;
    if (result == null) {
      return EmptyState(
        icon: Icons.landscape_outlined,
        title: 'Review your farm inputs',
        message:
            state.setupIssue ??
            'The current assumptions could not be calculated. Review the field, crop, and financial inputs.',
        action: FilledButton.icon(
          onPressed: () => context.go('/farm'),
          icon: const Icon(Icons.add),
          label: const Text('Set up farm'),
        ),
      );
    }
    final checks = state.constraints!;
    final alerts = AlertEngine().evaluate(farm, result, checks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Your farm, connected.',
          'See the whole operation. Explore what’s possible.',
          action: FilledButton.icon(
            onPressed: state.busy
                ? null
                : () {
                    context.go('/optimize');
                    state.optimize();
                  },
            icon: const Icon(Icons.auto_graph, size: 19),
            label: const Text('Explore farm plans'),
          ),
        ),
        ResponsiveGrid(
          children: [
            Metric(
              label: 'EXPECTED OPERATING INCOME',
              value: currency(result.operatingIncome, cc),
              icon: Icons.trending_up,
              note: '${currency(result.marginPerAcre, cc)} per acre',
              negative: result.operatingIncome < 0,
            ),
            Metric(
              label: 'CASH AFTER DEBT',
              value: currency(result.cashAfterDebt, cc),
              icon: Icons.account_balance_wallet_outlined,
              note: '${currency(result.debtService, cc)} annual debt service',
              negative: result.cashAfterDebt < 0,
            ),
            Metric(
              label: 'ANNUAL WATER USE',
              value: '${number(result.waterUsage)} ac-ft',
              icon: Icons.water_drop_outlined,
              note:
                  '${number(result.waterUsage / farm.acreage)} acre-feet per acre',
            ),
            Metric(
              label: 'PRACTICE ALIGNMENT',
              value: '${checks.satisfied} / ${checks.total}',
              icon: Icons.eco_outlined,
              note: 'Farmer-defined requirements satisfied',
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, size) {
            final canvas = SectionCard(
              title: 'Farm canvas',
              subtitle:
                  '${number(farm.acreage)} acres · ${farm.fields.length} fields · ${result.diversity} crops',
              action: IconButton(
                tooltip: 'Manage fields',
                onPressed: () => context.go('/farm'),
                icon: const Icon(Icons.north_east),
              ),
              child: FarmCanvas(
                farm: farm,
                onField: (field) => editField(context, state, field),
              ),
            );
            final resources = SectionCard(
              title: 'Operating boundaries',
              subtitle: 'Current plan against your requirements',
              action: IconButton(
                tooltip: 'Edit constraints',
                onPressed: () => context.go('/farm?tab=2'),
                icon: const Icon(Icons.tune),
              ),
              child: checks.checks.isEmpty
                  ? const Text(
                      'No constraints configured. Add boundaries before optimizing.',
                    )
                  : Column(
                      children: checks.checks
                          .take(5)
                          .map(
                            (check) => Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(check.name)),
                                      Icon(
                                        check.satisfied
                                            ? Icons.check_circle_outline
                                            : Icons.error_outline,
                                        color: check.satisfied
                                            ? FarmTheme.moss
                                            : FarmTheme.danger,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (check.utilization != null) ...[
                                    LinearProgressIndicator(
                                      value: check.utilization!.clamp(0, 1),
                                      minHeight: 6,
                                      borderRadius: BorderRadius.circular(4),
                                      color: check.satisfied
                                          ? FarmTheme.moss
                                          : FarmTheme.danger,
                                      backgroundColor: FarmTheme.cream,
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  Text(
                                    '${number(check.actual)} / ${number(check.limit)} · ${check.mode.name}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
            );
            if (size.maxWidth < 900) {
              return Column(
                children: [canvas, const SizedBox(height: 24), resources],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: canvas),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: resources),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (alerts.isNotEmpty)
          SectionCard(
            title: 'What deserves a closer look',
            subtitle: 'Calculated from your current plan',
            child: Column(
              children: alerts
                  .map(
                    (alert) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Notice(
                        alert.message,
                        error: alert.severity == AlertSeverity.critical,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Calculated outlook · ${humanSource(farm.provenance.source)} inputs · ${farm.settings.currencyCode} · Model estimates are conditional on the assumptions you enter.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String humanSource(DataSourceType source) => switch (source) {
  DataSourceType.sample => 'Sample',
  DataSourceType.userEntered => 'User supplied',
  DataSourceType.imported => 'Imported',
  DataSourceType.externalProvider => 'External provider',
  DataSourceType.configuredDefault => 'Configured default',
};
