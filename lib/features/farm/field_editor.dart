import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/farm_theme.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/farm_domain.dart';

/// Collects explicit crop IDs and validates the complete farm before saving.
Future<void> showFieldEditor(
  BuildContext context, {
  required Farm farm,
  Field? field,
  required Future<void> Function(Field) onSave,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _FieldEditor(farm: farm, field: field, onSave: onSave),
);

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.farm,
    required this.field,
    required this.onSave,
  });

  final Farm farm;
  final Field? field;
  final Future<void> Function(Field) onSave;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  final _form = GlobalKey<FormState>();
  late final String _id = widget.field?.id ?? const Uuid().v4();
  late final _name = TextEditingController(text: widget.field?.name ?? '');
  late final _acres = TextEditingController(
    text: widget.field?.acres.toString() ?? '',
  );
  late final _soil = TextEditingController(text: widget.field?.soilType ?? '');
  late final _yield = TextEditingController(
    text: widget.field?.yieldMultiplier.toString() ?? '1',
  );
  late final _compatibleIds = <String>{...?widget.field?.compatibleCropIds};
  late final _historyIds = <String>[...?widget.field?.cropHistory];
  late String _currentCropId = widget.field?.currentCropId ?? '';
  late bool _irrigated = widget.field?.irrigated ?? false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _acres, _soil, _yield]) {
      controller.dispose();
    }
    super.dispose();
  }

  Field _field() => Field(
    id: _id,
    name: _name.text.trim(),
    acres: double.tryParse(_acres.text) ?? 0,
    currentCropId: _currentCropId,
    compatibleCropIds: _compatibleIds.toList(),
    cropHistory: _historyIds,
    irrigated: _irrigated,
    soilType: _soil.text.trim(),
    yieldMultiplier: double.tryParse(_yield.text) ?? 0,
    provenance: Provenance(
      source: DataSourceType.userEntered,
      updatedAt: DateTime.now().toUtc(),
    ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final field = _field();
      widget.farm
          .copyWith(
            fields: [
              ...widget.farm.fields.where((item) => item.id != field.id),
              field,
            ],
          )
          .validate();
      await widget.onSave(field);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(() {
          _error = switch (failure) {
            DomainFailure() => failure.message,
            AppFailure() => failure.message,
            _ => 'The field could not be saved. Please try again.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _field();
    final crops = widget.farm.crops;
    final compatible = crops.where(draft.isCompatibleWith).toList();
    final currentIsValid =
        _currentCropId.isEmpty ||
        compatible.any((crop) => crop.id == _currentCropId);
    final cropNames = {for (final crop in crops) crop.id: crop.name};
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.field == null ? 'Add field' : 'Edit ${widget.field!.name}',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose the crops that can grow here, then assign a current crop. '
                    'A field without an assignment can be saved and completed later.',
                  ),
                  const SizedBox(height: 20),
                  AbsorbPointer(
                    absorbing: _saving,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter a field name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _acres,
                          decoration: const InputDecoration(
                            labelText: 'Area (acres)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            final acres = double.tryParse(value ?? '');
                            return acres == null ||
                                    !acres.isFinite ||
                                    acres <= 0
                                ? 'Enter an area greater than zero'
                                : null;
                          },
                        ),
                        SwitchListTile(
                          key: const ValueKey('field-irrigated'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Irrigated'),
                          value: _irrigated,
                          onChanged: (value) =>
                              setState(() => _irrigated = value),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Compatible crops',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (crops.isEmpty)
                          const Text(
                            'No crop profiles yet. Add a crop profile, then edit this field to choose compatible crops.',
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final crop in crops)
                              Tooltip(
                                message: crop.requiresIrrigation
                                    ? 'This crop requires an irrigated field.'
                                    : 'Allow this crop on this field.',
                                child: FilterChip(
                                  key: ValueKey('field-compatible-${crop.id}'),
                                  label: Text(crop.name),
                                  selected: _compatibleIds.contains(crop.id),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      _compatibleIds.add(crop.id);
                                    } else {
                                      _compatibleIds.remove(crop.id);
                                    }
                                  }),
                                ),
                              ),
                          ],
                        ),
                        if (!_irrigated &&
                            crops.any((crop) => crop.requiresIrrigation)) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Crops that require irrigation can only be assigned when this field is irrigated.',
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (compatible.isEmpty) ...[
                          const Text(
                            'No compatible crops selected. Choose a compatible crop above to set the current crop.',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!currentIsValid) ...[
                          const Text(
                            'The current crop is not compatible with this field. Choose a compatible crop or No current crop before saving.',
                            style: TextStyle(color: FarmTheme.danger),
                          ),
                          const SizedBox(height: 12),
                        ],
                        KeyedSubtree(
                          key: const ValueKey('field-current-crop'),
                          child: DropdownButtonFormField<String>(
                            // Reset the form field when eligibility changes, so a
                            // removed assignment is never a stale dropdown item.
                            key: ValueKey(
                              '${compatible.map((crop) => crop.id).join(',')}:$_currentCropId',
                            ),
                            initialValue: currentIsValid
                                ? _currentCropId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Current crop',
                            ),
                            isExpanded: true,
                            hint: const Text('Choose a compatible crop'),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('No current crop'),
                              ),
                              for (final crop in compatible)
                                DropdownMenuItem(
                                  value: crop.id,
                                  child: Text(crop.name),
                                ),
                            ],
                            validator: (_) => currentIsValid
                                ? null
                                : 'Choose a compatible crop or No current crop',
                            onChanged: (id) {
                              if (id != null) {
                                setState(() => _currentCropId = id);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text('Crop history · most recent first'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (
                              var index = 0;
                              index < _historyIds.length;
                              index++
                            )
                              InputChip(
                                label: Text(
                                  '${index + 1}. ${cropNames[_historyIds[index]] ?? 'Unavailable crop'}',
                                ),
                                onDeleted: () =>
                                    setState(() => _historyIds.removeAt(index)),
                              ),
                          ],
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('history-${_historyIds.length}'),
                          hint: const Text('Append a previous crop'),
                          items: [
                            for (final crop in crops)
                              DropdownMenuItem(
                                value: crop.id,
                                child: Text(crop.name),
                              ),
                          ],
                          onChanged: crops.isEmpty
                              ? null
                              : (id) {
                                  if (id != null) {
                                    setState(() => _historyIds.add(id));
                                  }
                                },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _soil,
                          decoration: const InputDecoration(
                            labelText: 'Soil type',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _yield,
                          decoration: const InputDecoration(
                            labelText: 'Yield multiplier',
                            helperText:
                                'Relative to the selected crop profile; 1 means unchanged.',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            final multiplier = double.tryParse(value ?? '');
                            return multiplier == null ||
                                    !multiplier.isFinite ||
                                    multiplier < 0
                                ? 'Enter a finite, non-negative multiplier'
                                : null;
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: FarmTheme.danger),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
