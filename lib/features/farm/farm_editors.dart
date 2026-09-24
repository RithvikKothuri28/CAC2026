import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../domain/farm_domain.dart';
import '../../core/widgets/model_editor.dart';
import '../workspace/workspace_controller.dart';
import 'field_editor.dart';

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

  await editModel(
    context,
    title: crop == null ? 'Add crop profile' : 'Edit ${crop.name}',
    initial: data,
    help:
        'Enter your crop assumptions. Costs are per acre in ${farm.settings.currencyCode}. Zero means no modeled cost or uncertainty; it is not a market estimate.',
    validate: (json) => updated(json).validate(),
    onSave: (json) => state.saveFarm(updated(json)),
  );
}

Future<void> editField(
  BuildContext context,
  WorkspaceController state, [
  Field? field,
]) async {
  final farm = state.farm!;
  await showFieldEditor(
    context,
    farm: farm,
    field: field,
    onSave: (entity) => state.saveFarm(
      farm.copyWith(
        fields: [
          ...farm.fields.where((value) => value.id != entity.id),
          entity,
        ],
      ),
    ),
  );
}

Future<void> editExpense(
  BuildContext context,
  WorkspaceController state, [
  Expense? expense,
]) async {
  final farm = state.farm!;
  await editModel(
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
    onSave: (json) => state.saveFarm(
      farm.copyWith(
        expenses: [
          ...farm.expenses.where((e) => e.id != json['id']),
          Expense.fromJson(json),
        ],
      ),
    ),
  );
}

Future<void> editDebt(
  BuildContext context,
  WorkspaceController state, [
  Debt? debt,
]) async {
  final farm = state.farm!;
  await editModel(
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
    onSave: (json) => state.saveFarm(
      farm.copyWith(
        debts: [
          ...farm.debts.where((e) => e.id != json['id']),
          Debt.fromJson(json),
        ],
      ),
    ),
  );
}

Future<void> editConstraint(
  BuildContext context,
  WorkspaceController state, [
  FarmConstraint? constraint,
]) async {
  final farm = state.farm!;
  await editModel(
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
    onSave: (json) => state.saveFarm(
      farm.copyWith(
        constraints: [
          ...farm.constraints.where((e) => e.id != json['id']),
          FarmConstraint.fromJson(json),
        ],
      ),
    ),
  );
}

Future<void> editFarmSettings(
  BuildContext context,
  WorkspaceController state,
) async {
  final farm = state.farm!;
  await editModel(
    context,
    title: 'Model assumptions & limits',
    initial: farm.settings.toJson(),
    help:
        'All values are editable inputs. Objective weights are fractions totaling 1. Uncertainty assumptions drive simulations; they are not externally verified.',
    validate: (json) =>
        farm.copyWith(settings: FarmSettings.fromJson(json)).validate(),
    onSave: (json) =>
        state.saveFarm(farm.copyWith(settings: FarmSettings.fromJson(json))),
  );
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
    onSave: (json) {
      final value = StressScenario.fromJson(json);
      return state.saveFarm(
        state.farm!.copyWith(
          scenarios: [
            ...state.farm!.scenarios.where((s) => s.id != value.id),
            value,
          ],
        ),
      );
    },
  );
  return result == null ? null : StressScenario.fromJson(result);
}
