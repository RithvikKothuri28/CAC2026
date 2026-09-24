import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/farm_domain.dart';
import '../../app/theme/farm_theme.dart';

String humanize(String key) => key
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match[1]}')
    .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

const inputLabels = <String, String>{
  'acres': 'Area (acres)',
  'yieldPerAcre': 'Expected yield / acre',
  'pricePerUnit': 'Expected price / yield unit',
  'yieldUnit': 'Yield unit (e.g. bushels)',
  'waterPerAcre': 'Water (acre-feet / acre)',
  'nitrogenPerAcre': 'Nitrogen (lb / acre)',
  'yieldVolatility': 'Yield coefficient of variation (0–1)',
  'priceVolatility': 'Price coefficient of variation (0–1)',
  'annualInterestRate': 'Annual interest rate (fraction)',
  'inflationRate': 'Annual inflation (fraction)',
  'priceGrowthRate': 'Annual price growth (fraction)',
  'expenseInflationRate': 'Annual variable cost inflation (fraction)',
  'limit': 'Limit (fractions for share constraints)',
  'weatherCorrelation': 'Yield correlation across fields (0–1)',
  'marketCorrelation': 'Price correlation across crops (0–1)',
  'liquidityReserve': 'Starting cash reserve',
  'alertUtilizationThreshold': 'Alert utilization threshold (fraction)',
  'equipmentFailureProbability': 'Annual equipment failure probability (0–1)',
  'waterAvailabilityMultiplier': 'Water limit multiplier',
  'currencyCode': 'ISO currency code',
  'minimumRotationYears': 'Years before repeating rotation family',
};

Future<Map<String, dynamic>?> editModel(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> initial,
  required void Function(Map<String, dynamic>) validate,
  Map<String, Map<String, String>> choices = const {},
  String? help,
  Future<void> Function(Map<String, dynamic>)? onSave,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _ModelEditor(
    title: title,
    initial: initial,
    validate: validate,
    choices: choices,
    help: help,
    onSave: onSave,
  ),
);

class _ModelEditor extends StatefulWidget {
  const _ModelEditor({
    required this.title,
    required this.initial,
    required this.validate,
    required this.choices,
    this.help,
    this.onSave,
  });
  final String title;
  final Map<String, dynamic> initial;
  final void Function(Map<String, dynamic>) validate;
  final Map<String, Map<String, String>> choices;
  final String? help;
  final Future<void> Function(Map<String, dynamic>)? onSave;
  @override
  State<_ModelEditor> createState() => _ModelEditorState();
}

class _ModelEditorState extends State<_ModelEditor> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  late Map<String, dynamic> value;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    value = jsonDecode(jsonEncode(widget.initial)) as Map<String, dynamic>;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(Map<String, dynamic> map, String key, String path) {
    final item = map[key];
    final label = inputLabels[key] ?? humanize(key);
    final integer = const [
      'iterations',
      'seed',
      'exhaustiveLimit',
      'candidateLimit',
      'frontierLimit',
      'minimumRotationYears',
    ].contains(key);
    if (item is Map) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key == 'weights'
                  ? 'Objective weights · fractions must total 1'
                  : label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            ...fields(item.cast<String, dynamic>(), '$path.'),
          ],
        ),
      );
    }
    if (item is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: item,
        onChanged: (checked) => setState(() => map[key] = checked),
      );
    }
    final choice = widget.choices[key];
    if (item is List && choice != null) {
      final selected = List<String>.from(item);
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(key == 'cropHistory' ? '$label · most recent first' : label),
            const SizedBox(height: 8),
            if (key == 'cropHistory') ...[
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < selected.length; i++)
                    InputChip(
                      label: Text(
                        '${i + 1}. ${choice[selected[i]] ?? selected[i]}',
                      ),
                      onDeleted: () => setState(() {
                        selected.removeAt(i);
                        map[key] = selected;
                      }),
                    ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: null,
                hint: const Text('Append a previous crop'),
                items: choice.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null) setState(() => map[key] = [...selected, id]);
                },
              ),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: choice.entries
                    .map(
                      (entry) => FilterChip(
                        label: Text(entry.value),
                        selected: selected.contains(entry.key),
                        onSelected: (checked) => setState(() {
                          checked
                              ? selected.add(entry.key)
                              : selected.remove(entry.key);
                          map[key] = selected;
                        }),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      );
    }
    if (choice != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          initialValue: choice.containsKey(item) ? item as String : null,
          decoration: InputDecoration(labelText: label),
          isExpanded: true,
          items: choice.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          validator: (input) => input == null ? 'Choose a value' : null,
          onChanged: (input) => map[key] = input,
        ),
      );
    }
    final control = _controllers.putIfAbsent(
      path,
      () => TextEditingController(
        text: item is List ? item.join(', ') : item?.toString() ?? '',
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: control,
        decoration: InputDecoration(
          labelText: label,
          helperText: item is List ? 'Separate values with commas' : null,
        ),
        keyboardType: item is num
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        minLines: 1,
        maxLines: key == 'notes' ? 4 : 1,
        validator: (input) {
          if (item is num) {
            final parsed = num.tryParse(input ?? '');
            if (parsed == null || !parsed.isFinite) {
              return 'Enter a finite number';
            }
            if (integer && parsed != parsed.roundToDouble()) {
              return 'Enter a whole number';
            }
          } else if ([
                'name',
                'yieldUnit',
                'currencyCode',
                'rotationFamily',
              ].contains(key) &&
              (input ?? '').trim().isEmpty) {
            return 'This value is required';
          }
          return null;
        },
        onSaved: (input) {
          map[key] = item is num && integer
              ? num.parse(input!).toInt()
              : item is num
              ? double.parse(input!)
              : item is List
              ? (input ?? '')
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList()
              : (input ?? '').trim();
        },
      ),
    );
  }

  List<Widget> fields(Map<String, dynamic> map, String prefix) => map.keys
      .where(
        (key) => ![
          'id',
          'schemaVersion',
          'provenance',
          'updatedAt',
          'source',
        ].contains(key),
      )
      .map((key) => field(map, key, '$prefix$key'))
      .toList();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.help != null) ...[
                  Text(
                    widget.help!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                ],
                AbsorbPointer(
                  absorbing: saving,
                  child: Column(children: fields(value, '')),
                ),
                if (saving) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!, style: const TextStyle(color: FarmTheme.danger)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  if (!_form.currentState!.validate()) return;
                  _form.currentState!.save();
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    if (value.containsKey('provenance')) {
                      value['provenance'] = Provenance(
                        source: DataSourceType.userEntered,
                        updatedAt: DateTime.now().toUtc(),
                      ).toJson();
                    }
                    widget.validate(value);
                    await widget.onSave?.call(value);
                    if (context.mounted) Navigator.pop(context, value);
                  } catch (failure) {
                    if (mounted) setState(() => error = failure.toString());
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
