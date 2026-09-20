import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/charts.dart';
import '../farm/farm_editors.dart';
import '../optimization/optimization_page.dart';
import '../workspace/workspace_controller.dart';

class ScenarioPage extends StatelessWidget {
  const ScenarioPage({super.key, required this.state});
  final WorkspaceController state;
  @override
  Widget build(BuildContext context) {
    if (!state.ready) {
      return EmptyState(
        icon: Icons.science_outlined,
        title: 'Set up your farm first',
        message:
            'Scenarios adjust real farm assumptions and re-run the optimizer.',
        action: FilledButton(
          onPressed: () => context.go('/farm'),
          child: const Text('Set up farm'),
        ),
      );
    }
    final farm = state.farm!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Make room for “what if.”',
          'Change assumptions and calculate a new response.',
          action: FilledButton.icon(
            onPressed: state.busy ? null : () => editScenario(context, state),
            icon: const Icon(Icons.add),
            label: const Text('Create scenario'),
          ),
        ),
        if (farm.scenarios.isEmpty)
          const Notice(
            'Create a scenario with your own market, cost, production, water, and debt assumptions.',
          ),
        ...farm.scenarios.map(
          (scenario) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SectionCard(
              title: scenario.name,
              subtitle:
                  'Price ×${number(scenario.priceMultiplier)} · Yield ×${number(scenario.yieldMultiplier)} · Fertilizer ×${number(scenario.fertilizerMultiplier)} · Water limit ×${number(scenario.waterAvailabilityMultiplier)}',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: state.busy
                        ? null
                        : () => state.runScenario(scenario),
                    icon: const Icon(Icons.auto_graph),
                    label: const Text('Re-optimize scenario'),
                  ),
                  OutlinedButton(
                    onPressed: state.busy
                        ? null
                        : () => editScenario(context, state, scenario),
                    child: const Text('Inspect & edit'),
                  ),
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () async {
                            if (await confirmAction(
                              context,
                              'Delete scenario?',
                              'Remove ${scenario.name} from this farm?',
                            )) {
                              await state.perform(
                                'Deleting scenario',
                                () => state.saveFarm(
                                  farm.copyWith(
                                    scenarios: farm.scenarios
                                        .where((s) => s.id != scenario.id)
                                        .toList(),
                                  ),
                                ),
                              );
                            }
                          },
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (state.scenarioResult != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: '${state.scenarioName} · calculated response',
            subtitle:
                '${number(state.scenarioResult!.diagnostics.plansEvaluated)} evaluated · ${number(state.scenarioResult!.diagnostics.feasiblePlans)} feasible',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...state.scenarioResult!.warnings.map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Notice(warning),
                  ),
                ),
                if (state.scenarioResult!.recommended == null)
                  const Notice(
                    'No feasible alternative found under these scenario assumptions.',
                    error: true,
                  )
                else ...[
                  comparisonTable(
                    context,
                    state.scenarioResult!.current.financial,
                    state.scenarioResult!.recommended!.financial,
                    farm.settings.currencyCode,
                  ),
                  const SizedBox(height: 24),
                  FarmCanvas(
                    farm: state.scenarioFarm!,
                    plan: state.scenarioResult!.recommended!.plan,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
