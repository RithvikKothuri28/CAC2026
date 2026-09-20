import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../domain/farm_domain.dart';
import '../../core/widgets/model_editor.dart';
import '../workspace/workspace_controller.dart';

Provenance entered() => Provenance(
  source: DataSourceType.userEntered,
  updatedAt: DateTime.now().toUtc(),
);
String newId() => const Uuid().v4();

Future<void> editCrop(
  BuildContext context,
  WorkspaceController state, [
  CropProfile? crop,
]) async {
  final farm = state.farm!;
  final data =
      crop?.toJson() ??
      {
        'id': newId(),
        'name': '',
        'yieldPerAcre': 0.0,
        'pricePerUnit': 0.0,
        'yieldUnit': '',
        'seedCostPerAcre': 0.0,
        'fertilizerCostPerAcre': 0.0,
        'chemicalCostPerAcre': 0.0,
        'waterCostPerAcre': 0.0,
        'laborCostPerAcre': 0.0,
        'fuelCostPerAcre': 0.0,
        'equipmentCostPerAcre': 0.0,
        'waterPerAcre': 0.0,
        'nitrogenPerAcre': 0.0,
        'yieldVolatility': 0.0,
        'priceVolatility': 0.0,
        'rotationFamily': '',
        'minimumRotationYears': 0,
        'requiresIrrigation': false,
        'inputs': <String>[],
        'providesSoilCover': false,
        'provenance': entered().toJson(),
      };
  Farm updated(Map<String, dynamic> json) {
    final entity = CropProfile.fromJson(json);
    return farm.copyWith(
      crops: [...farm.crops.where((v) => v.id != entity.id), entity],
    );
  }

  final result = await editModel(
    context,
    title: crop == null ? 'Add crop profile' : 'Edit ${crop.name}',
    initial: data,
    help:
        'Enter your crop assumptions. Costs are per acre in ${farm.settings.currencyCode}. Zero means no modeled cost or uncertainty; it is not a market estimate.',
    validate: (json) => updated(json).validate(),
  );
  if (result != null) {
    await state.perform(
      'Saving crop profile',
      () => state.saveFarm(updated(result)),
    );
  }
}

Future<void> editField(
  BuildContext context,
  WorkspaceController state, [
  Field? field,
]) async {
  final farm = state.farm!;
  if (farm.crops.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a crop profile before adding fields.')),
    );
    return;
  }
  final cropChoices = {for (final crop in farm.crops) crop.id: crop.name};
  final data =
      field?.toJson() ??
      {
        'id': newId(),
        'name': '',
        'acres': 0.0,
        'currentCropId': farm.crops.first.id,
        'compatibleCropIds': farm.crops.map((c) => c.id).toList(),
        'cropHistory': <String>[],
        'irrigated': false,
        'soilType': '',
        'yieldMultiplier': 1.0,
        'provenance': entered().toJson(),
      };
  Farm updated(Map<String, dynamic> json) {
    final entity = Field.fromJson(json);
    return farm.copyWith(
      fields: [...farm.fields.where((v) => v.id != entity.id), entity],
    );
  }

  final result = await editModel(
    context,
    title: field == null ? 'Add field' : 'Edit ${field.name}',
    initial: data,
    choices: {
      'currentCropId': cropChoices,
      'compatibleCropIds': cropChoices,
      'cropHistory': cropChoices,
    },
    help:
        'Select the crops that can grow here. Yield multiplier is relative to each crop profile. History starts with last year.',
    validate: (json) => updated(json).validate(),
  );
  if (result != null) {
    await state.perform('Saving field', () => state.saveFarm(updated(result)));
  }
}

Future<void> editExpense(
  BuildContext context,
  WorkspaceController state, [
  Expense? expense,
]) async {
  final farm = state.farm!;
  final result = await editModel(
    context,
    title: expense == null ? 'Add fixed expense' : 'Edit expense',
    initial:
        expense?.toJson() ??
        {
          'id': newId(),
          'name': '',
          'annualAmount': 0.0,
          'inflationRate': 0.0,
          'provenance': entered().toJson(),
        },
    help: 'Farm-wide annual expenses. Per-acre inputs belong in crop profiles.',
    validate: (json) => farm
        .copyWith(
          expenses: [
            ...farm.expenses.where((e) => e.id != json['id']),
            Expense.fromJson(json),
          ],
        )
        .validate(),
  );
  if (result != null) {
    await state.perform(
      'Saving expense',
      () => state.saveFarm(
        farm.copyWith(
          expenses: [
            ...farm.expenses.where((e) => e.id != result['id']),
            Expense.fromJson(result),
          ],
        ),
      ),
    );
  }
}

Future<void> editDebt(
  BuildContext context,
  WorkspaceController state, [
  Debt? debt,
]) async {
  final farm = state.farm!;
  final result = await editModel(
    context,
    title: debt == null ? 'Add debt' : 'Edit debt',
    initial:
        debt?.toJson() ??
        {
          'id': newId(),
          'name': '',
          'balance': 0.0,
          'annualInterestRate': 0.0,
          'annualPayment': 0.0,
          'provenance': entered().toJson(),
        },
    help:
        'Enter the balance, annual rate as a fraction, and scheduled annual payment.',
    validate: (json) => farm
        .copyWith(
          debts: [
            ...farm.debts.where((e) => e.id != json['id']),
            Debt.fromJson(json),
          ],
        )
        .validate(),
  );
  if (result != null) {
    await state.perform(
      'Saving debt',
      () => state.saveFarm(
        farm.copyWith(
          debts: [
            ...farm.debts.where((e) => e.id != result['id']),
            Debt.fromJson(result),
          ],
        ),
      ),
    );
  }
}

Future<void> editConstraint(
  BuildContext context,
  WorkspaceController state, [
  FarmConstraint? constraint,
]) async {
  final farm = state.farm!;
  final result = await editModel(
    context,
    title: constraint == null ? 'Add operating constraint' : 'Edit constraint',
    initial:
        constraint?.toJson() ??
        {
          'id': newId(),
          'name': '',
          'kind': ConstraintKind.maxWater.name,
          'mode': ConstraintMode.hard.name,
          'limit': 0.0,
          'restrictedInputs': <String>[],
        },
    choices: {
      'kind': {
        for (final kind in ConstraintKind.values)
          kind.name: humanize(kind.name),
      },
      'mode': {
        for (final mode in ConstraintMode.values)
          mode.name: humanize(mode.name),
      },
    },
    help:
        'Water: acre-feet. Nitrogen: lb. Money: ${farm.settings.currencyCode}. Concentration and soil cover: fractions 0–1. Diversity: crop count. Rotation/restricted input rules do not use the numeric limit.',
    validate: (json) => farm
        .copyWith(
          constraints: [
            ...farm.constraints.where((e) => e.id != json['id']),
            FarmConstraint.fromJson(json),
          ],
        )
        .validate(),
  );
  if (result != null) {
    await state.perform(
      'Saving constraint',
      () => state.saveFarm(
        farm.copyWith(
          constraints: [
            ...farm.constraints.where((e) => e.id != result['id']),
            FarmConstraint.fromJson(result),
          ],
        ),
      ),
    );
  }
}

Future<void> editFarmSettings(
  BuildContext context,
  WorkspaceController state,
) async {
  final farm = state.farm!;
  final result = await editModel(
    context,
    title: 'Model assumptions & limits',
    initial: farm.settings.toJson(),
    help:
        'All values are editable inputs. Objective weights are fractions totaling 1. Uncertainty assumptions drive simulations; they are not externally verified.',
    validate: (json) =>
        farm.copyWith(settings: FarmSettings.fromJson(json)).validate(),
  );
  if (result != null) {
    await state.perform(
      'Saving assumptions',
      () => state.saveFarm(
        farm.copyWith(settings: FarmSettings.fromJson(result)),
      ),
    );
  }
}

Future<StressScenario?> editScenario(
  BuildContext context,
  WorkspaceController state, [
  StressScenario? scenario,
]) async {
  final result = await editModel(
    context,
    title: scenario == null ? 'Create scenario' : 'Edit scenario',
    initial:
        scenario?.toJson() ??
        {
          'id': newId(),
          'name': '',
          'priceMultiplier': 1.0,
          'yieldMultiplier': 1.0,
          'fertilizerMultiplier': 1.0,
          'fuelMultiplier': 1.0,
          'laborMultiplier': 1.0,
          'waterAvailabilityMultiplier': 1.0,
          'interestRateMultiplier': 1.0,
          'equipmentCostAddition': 0.0,
        },
    help:
        'Multipliers: 1 means unchanged, 0.8 means a 20% reduction, 1.2 means a 20% increase. This creates a separate scenario; your current farm stays saved.',
    validate: (json) {
      ScenarioEngine().apply(state.farm!, StressScenario.fromJson(json));
    },
  );
  if (result == null) return null;
  final value = StressScenario.fromJson(result);
  await state.perform('Saving scenario', () async {
    await state.saveFarm(
      state.farm!.copyWith(
        scenarios: [
          ...state.farm!.scenarios.where((s) => s.id != value.id),
          value,
        ],
      ),
    );
  });
  return value;
}
