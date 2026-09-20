import 'package:flutter/material.dart';
import '../../app/theme/farm_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/model_editor.dart';
import '../dashboard/dashboard_page.dart';
import '../workspace/workspace_controller.dart';
import 'farm_editors.dart';

class FarmPage extends StatelessWidget {
  const FarmPage({super.key, required this.state, this.initialTab = 0});
  final WorkspaceController state;
  final int initialTab;
  Future<void> remove(
    BuildContext context,
    String label,
    Future<void> Function() task,
  ) async {
    if (await confirmAction(
      context,
      'Delete $label?',
      'This removes the saved record. Existing calculated results will be cleared.',
    )) {
      await state.perform('Deleting record', task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farm = state.farm!;
    final cc = farm.settings.currencyCode;
    Widget row(
      String title,
      String detail,
      VoidCallback edit,
      VoidCallback delete,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(detail),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit $title',
              onPressed: state.busy ? null : edit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Delete $title',
              onPressed: state.busy ? null : delete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
      ),
    );
    final sections = [
      SectionCard(
        title: 'Fields',
        subtitle: 'Your land, crop compatibility, and rotation history',
        action: FilledButton.tonalIcon(
          onPressed: state.busy ? null : () => editField(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Add field'),
        ),
        child: Column(
          children: [
            if (farm.fields.isEmpty)
              const Notice('Add crop profiles first, then define your fields.'),
            if (farm.fields.isNotEmpty) ...[
              FarmCanvas(
                farm: farm,
                onField: (field) => editField(context, state, field),
              ),
              const SizedBox(height: 14),
            ],
            ...farm.fields.map(
              (field) => row(
                field.name,
                '${number(field.acres)} acres · ${farm.crop(field.currentCropId).name} · ${field.irrigated ? 'Irrigated' : 'Rainfed'} · ${humanSource(field.provenance.source)}',
                () => editField(context, state, field),
                () => remove(
                  context,
                  field.name,
                  () => state.saveFarm(
                    farm.copyWith(
                      fields: farm.fields
                          .where((f) => f.id != field.id)
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Crop profiles',
        subtitle: 'Prices, yields, inputs, resource needs, and uncertainty',
        action: FilledButton.tonalIcon(
          onPressed: state.busy ? null : () => editCrop(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Add crop'),
        ),
        child: Column(
          children: [
            if (farm.crops.isEmpty)
              const Notice(
                'Create a crop using your own yield, price, and input assumptions.',
              ),
            ...farm.crops.map(
              (crop) => row(
                crop.name,
                '${number(crop.yieldPerAcre)} ${crop.yieldUnit}/acre · ${currency(crop.pricePerUnit, cc)}/unit · ${currency(crop.costPerAcre, cc)}/acre inputs · ${humanSource(crop.provenance.source)}',
                () => editCrop(context, state, crop),
                () => remove(
                  context,
                  crop.name,
                  () => state.saveFarm(
                    farm.copyWith(
                      crops: farm.crops.where((c) => c.id != crop.id).toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A crop referenced by a field or its history cannot be deleted until those references are updated.',
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Farmer-defined constraints',
        subtitle:
            'Hard constraints must pass. Preferences contribute to practice alignment.',
        action: FilledButton.tonalIcon(
          onPressed: state.busy ? null : () => editConstraint(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Add rule'),
        ),
        child: Column(
          children: [
            if (farm.constraints.isEmpty)
              const Notice(
                'No boundaries configured. Add your operating limits.',
              ),
            ...farm.constraints.map(
              (constraint) => row(
                constraint.name,
                '${humanize(constraint.kind.name)} · ${number(constraint.limit)} · ${constraint.mode.name}',
                () => editConstraint(context, state, constraint),
                () => remove(
                  context,
                  constraint.name,
                  () => state.saveFarm(
                    farm.copyWith(
                      constraints: farm.constraints
                          .where((c) => c.id != constraint.id)
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Column(
        children: [
          SectionCard(
            title: 'Fixed operating expenses',
            subtitle: 'Annual farm-wide costs, separate from crop inputs',
            action: FilledButton.tonalIcon(
              onPressed: state.busy ? null : () => editExpense(context, state),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
            child: Column(
              children: [
                if (farm.expenses.isEmpty)
                  const Text('No fixed expenses entered.'),
                ...farm.expenses.map(
                  (expense) => row(
                    expense.name,
                    '${currency(expense.annualAmount, cc)} / year · ${percentage(expense.inflationRate)} inflation',
                    () => editExpense(context, state, expense),
                    () => remove(
                      context,
                      expense.name,
                      () => state.saveFarm(
                        farm.copyWith(
                          expenses: farm.expenses
                              .where((e) => e.id != expense.id)
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Debt obligations',
            subtitle: 'Balance, interest, and annual service',
            action: FilledButton.tonalIcon(
              onPressed: state.busy ? null : () => editDebt(context, state),
              icon: const Icon(Icons.add),
              label: const Text('Add debt'),
            ),
            child: Column(
              children: [
                if (farm.debts.isEmpty) const Text('No debt entered.'),
                ...farm.debts.map(
                  (debt) => row(
                    debt.name,
                    '${currency(debt.balance, cc)} balance · ${percentage(debt.annualInterestRate)} interest · ${currency(debt.annualPayment, cc)}/year',
                    () => editDebt(context, state, debt),
                    () => remove(
                      context,
                      debt.name,
                      () => state.saveFarm(
                        farm.copyWith(
                          debts: farm.debts
                              .where((d) => d.id != debt.id)
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'The farm behind the numbers.',
          '${farm.fields.length} fields · ${number(farm.acreage)} acres · ${farm.crops.length} crop options',
          action: OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () => editFarmSettings(context, state),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Model assumptions'),
          ),
        ),
        _FarmTabs(
          key: ValueKey(initialTab),
          initial: initialTab,
          sections: sections,
        ),
        const SizedBox(height: 24),
        const Notice(
          'Edits invalidate previous calculations. Re-run optimization and risk analysis after changing inputs.',
        ),
      ],
    );
  }
}

class _FarmTabs extends StatefulWidget {
  const _FarmTabs({super.key, required this.initial, required this.sections});
  final int initial;
  final List<Widget> sections;
  @override
  State<_FarmTabs> createState() => _FarmTabsState();
}

class _FarmTabsState extends State<_FarmTabs> {
  late int index = widget.initial.clamp(0, 3);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    selectedColor: FarmTheme.forest.withValues(alpha: .12),
                    label: Text(
                      ['Fields', 'Crops', 'Constraints', 'Finances'][i],
                    ),
                    selected: index == i,
                    onSelected: (_) => setState(() => index = i),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      widget.sections[index],
    ],
  );
}
