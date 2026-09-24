import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/model_editor.dart';
import '../../data/data.dart';
import '../farm/farm_editors.dart';
import '../workspace/workspace_controller.dart';

class HarvestPage extends StatefulWidget {
  const HarvestPage({super.key, required this.state});
  final WorkspaceController state;
  @override
  State<HarvestPage> createState() => _HarvestPageState();
}

class _HarvestPageState extends State<HarvestPage> {
  late final stream = widget.state.repository!.watchEntities(
    widget.state.farm!.id,
    EntityKind.harvestBatches,
  );
  Future<void> edit([StoredEntity? record]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchEditor(initial: record?.data),
    );
    if (result == null) return;
    final state = widget.state;
    final metadata = {...?record?.data}
      ..removeWhere(
        (key, _) => HarvestPassportService.allowedFields.contains(key),
      );
    await state.perform(
      'Saving harvest batch',
      () => state.repository!.saveEntity(
        state.farm!.id,
        EntityKind.harvestBatches,
        StoredEntity(id: record?.id ?? newId(), data: {...metadata, ...result}),
      ),
    );
  }

  Future<void> publish(StoredEntity record) async {
    final state = widget.state;
    final choices = HarvestPassportService.allowedFields
        .where(
          (key) =>
              record.data[key] != null &&
              record.data[key].toString().isNotEmpty,
        )
        .toList();
    final selected = <String>{'crop'};
    final fields = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Choose exactly what becomes public'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Notice(
                    'These selected farmer-supplied records will be accessible to anyone with the link. Review notes and events for private information.',
                  ),
                  const SizedBox(height: 12),
                  ...choices.map(
                    (key) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(humanize(key)),
                      subtitle: Text(jsonEncode(record.data[key])),
                      value: selected.contains(key),
                      onChanged: key == 'crop'
                          ? null
                          : (checked) => setState(() {
                              checked == true
                                  ? selected.add(key)
                                  : selected.remove(key);
                            }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Publish selected fields'),
            ),
          ],
        ),
      ),
    );
    if (fields == null) return;
    await state.perform('Publishing selected harvest data', () async {
      final id = await state.cloud!.passports.publish(
        farmId: state.farm!.id,
        batchId: record.id,
        fields: fields,
      );
      await state.repository!.saveEntity(
        state.farm!.id,
        EntityKind.harvestBatches,
        StoredEntity(
          id: record.id,
          data: {...record.data, 'passportId': id, 'publishedFields': fields},
        ),
      );
      if (mounted) await showQr(id);
    });
  }

  Future<void> showQr(String id) async {
    final url = widget.state.cloud!.passports.publicUrl(id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Public Harvest Passport'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(data: url, size: 240, backgroundColor: Colors.white),
              const SizedBox(height: 16),
              SelectableText(url),
              const SizedBox(height: 12),
              const Text('Farmer supplied · not independently verified'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
            },
            child: const Text('Copy link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final canPublish =
        (state.cloud?.features.harvestPublishingEnabled ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'A record of your harvest.',
          'Private batch records. Public only when you choose.',
          action: FilledButton.icon(
            onPressed: state.busy ? null : edit,
            icon: const Icon(Icons.add),
            label: const Text('Add harvest batch'),
          ),
        ),
        if (!canPublish) ...[
          Notice(
            'Public publishing is disabled for this deployment. Private harvest records can still be saved.',
          ),
          const SizedBox(height: 24),
        ],
        StreamBuilder<List<StoredEntity>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Notice(snapshot.error.toString(), error: true);
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return const SectionCard(
                title: 'Your first harvest record',
                child: Text(
                  'Record a crop, field, dates, practices, inputs, handling, and storage events. Farm financial information is never part of a public passport.',
                ),
              );
            }
            return Column(
              children: snapshot.data!
                  .map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: SectionCard(
                        title:
                            record.data['crop'] as String? ?? 'Harvest batch',
                        subtitle:
                            '${record.data['field'] ?? 'Field not provided'} · Farmer supplied',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (record.data['harvestDate'] != null)
                              Text('Harvested ${record.data['harvestDate']}'),
                            if (record.data['notes'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(record.data['notes'] as String),
                              ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => edit(record),
                                  child: const Text('View & edit'),
                                ),
                                if (canPublish)
                                  FilledButton.tonalIcon(
                                    onPressed: state.busy
                                        ? null
                                        : () => publish(record),
                                    icon: const Icon(Icons.publish_outlined),
                                    label: Text(
                                      record.data['passportId'] == null
                                          ? 'Publish passport'
                                          : 'Update publication',
                                    ),
                                  ),
                                if (canPublish &&
                                    record.data['passportId'] != null) ...[
                                  OutlinedButton.icon(
                                    onPressed: state.busy
                                        ? null
                                        : () => state.perform(
                                            'Opening passport',
                                            () => showQr(
                                              record.data['passportId']
                                                  as String,
                                            ),
                                          ),
                                    icon: const Icon(Icons.qr_code),
                                    label: const Text('QR & link'),
                                  ),
                                  TextButton(
                                    onPressed: state.busy
                                        ? null
                                        : () async {
                                            if (await confirmAction(
                                              context,
                                              'Unpublish passport?',
                                              'The public link will stop exposing this passport. Your private batch remains saved.',
                                            )) {
                                              await state.perform(
                                                'Unpublishing passport',
                                                () async {
                                                  await state.cloud!.passports
                                                      .unpublish(
                                                        farmId: state.farm!.id,
                                                        passportId:
                                                            record.data['passportId']
                                                                as String,
                                                      );
                                                  final data = {...record.data}
                                                    ..remove('passportId')
                                                    ..remove('publishedFields');
                                                  await state.repository!
                                                      .saveEntity(
                                                        state.farm!.id,
                                                        EntityKind
                                                            .harvestBatches,
                                                        StoredEntity(
                                                          id: record.id,
                                                          data: data,
                                                        ),
                                                      );
                                                },
                                              );
                                            }
                                          },
                                    child: const Text('Unpublish'),
                                  ),
                                ],
                                TextButton(
                                  onPressed: state.busy
                                      ? null
                                      : () async {
                                          if (await confirmAction(
                                            context,
                                            'Delete harvest batch?',
                                            'Remove the private batch and its published passport?',
                                          )) {
                                            await state.perform(
                                              'Deleting harvest batch',
                                              () async {
                                                if (record.data['passportId'] !=
                                                        null &&
                                                    state.cloud != null) {
                                                  await state.cloud!.passports
                                                      .unpublish(
                                                        farmId: state.farm!.id,
                                                        passportId:
                                                            record.data['passportId']
                                                                as String,
                                                      );
                                                }
                                                await state.repository!
                                                    .deleteEntity(
                                                      state.farm!.id,
                                                      EntityKind.harvestBatches,
                                                      record.id,
                                                    );
                                              },
                                            );
                                          }
                                        },
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                            if (record.data['passportId'] != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Text(
                                  'Edits remain private until you update the publication.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _BatchEditor extends StatefulWidget {
  const _BatchEditor({this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<_BatchEditor> createState() => _BatchEditorState();
}

class _BatchEditorState extends State<_BatchEditor> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  static const keys = [
    'crop',
    'field',
    'plantingDate',
    'harvestDate',
    'practices',
    'inputRecords',
    'handlingEvents',
    'storageEvents',
    'notes',
  ];
  static const eventKeys = ['inputRecords', 'handlingEvents', 'storageEvents'];
  @override
  void initState() {
    super.initState();
    for (final key in keys) {
      final value = widget.initial?[key];
      final text = value is List
          ? (eventKeys.contains(key)
                ? value
                      .map(
                        (v) =>
                            '${v['name']} | ${v['date'] ?? ''} | ${v['details'] ?? ''}',
                      )
                      .join('\n')
                : value.join(', '))
          : value?.toString() ?? '';
      controllers[key] = TextEditingController(text: text);
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool validDate(String input) {
    final date = DateTime.tryParse(input);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input) &&
        date != null &&
        date.toIso8601String().substring(0, 10) == input;
  }

  List<Map<String, String>> events(String input) =>
      input.split('\n').where((s) => s.trim().isNotEmpty).map((line) {
        final parts = line.split('|').map((s) => s.trim()).toList();
        if (parts.length > 3 || parts.first.isEmpty) {
          throw const FormatException(
            'Use name | date | details, one event per line.',
          );
        }
        if (parts.length > 1 && parts[1].isNotEmpty && !validDate(parts[1])) {
          throw const FormatException('Use a valid YYYY-MM-DD event date.');
        }
        return {
          'name': parts[0],
          if (parts.length > 1 && parts[1].isNotEmpty) 'date': parts[1],
          if (parts.length > 2 && parts[2].isNotEmpty) 'details': parts[2],
        };
      }).toList();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Harvest batch'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'All records are farmer supplied. Only the crop is required; add the information you have.',
              ),
              const SizedBox(height: 20),
              for (final key in keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: controllers[key],
                    decoration: InputDecoration(
                      labelText: humanize(key),
                      helperText: key.endsWith('Date')
                          ? 'YYYY-MM-DD'
                          : eventKeys.contains(key)
                          ? 'One event per line: name | YYYY-MM-DD | details'
                          : key == 'practices'
                          ? 'Separate practices with commas'
                          : null,
                    ),
                    minLines: eventKeys.contains(key) || key == 'notes' ? 2 : 1,
                    maxLines: eventKeys.contains(key) || key == 'notes' ? 5 : 1,
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (key == 'crop' && text.isEmpty) {
                        return 'Enter the harvested crop';
                      }
                      if (text.isEmpty) return null;
                      if (key.endsWith('Date') && !validDate(text)) {
                        return 'Enter a valid YYYY-MM-DD date';
                      }
                      if (eventKeys.contains(key)) {
                        try {
                          events(text);
                        } catch (error) {
                          return error.toString();
                        }
                      }
                      if (!eventKeys.contains(key) &&
                          text.length >
                              (key == 'notes'
                                  ? 2000
                                  : key == 'practices'
                                  ? 8000
                                  : 200)) {
                        return 'This value is too long';
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          final result = <String, dynamic>{
            'schemaVersion': 1,
            'provenance': 'farmerSupplied',
          };
          for (final key in keys) {
            final text = controllers[key]!.text.trim();
            if (text.isNotEmpty) {
              result[key] = eventKeys.contains(key)
                  ? events(text)
                  : key == 'practices'
                  ? text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList()
                  : text;
            }
          }
          Navigator.pop(context, result);
        },
        child: const Text('Save private record'),
      ),
    ],
  );
}
