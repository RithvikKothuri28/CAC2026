import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/model_editor.dart';
import '../../data/data.dart';
import '../auth/auth_dialog.dart';
import '../farm/farm_editors.dart';
import '../workspace/workspace_controller.dart';

Future<void> showExport(BuildContext context, String title, String text) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard.')),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy JSON'),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final WorkspaceController state;
  Future<void> import(BuildContext context) async {
    var enteredText = '';
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import farm JSON'),
        content: SizedBox(
          width: 600,
          child: TextField(
            onChanged: (value) => enteredText = value,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Paste a FarmTwin export',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredText),
            child: const Text('Validate & import'),
          ),
        ],
      ),
    );
    if (text != null) {
      await state.perform('Importing farm', () async {
        await state.saveFarm(
          const FarmExportService().importFarm(text, id: newId()),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final farm = state.farm!;
    final cloud = state.cloud;
    final privacy = cloud?.privacy.current;
    Future<void> updatePrivacy(UserSettings settings) =>
        state.perform('Saving privacy settings', () async {
          final uid = cloud!.auth.currentUser?.uid;
          if (uid == null) {
            throw const AuthenticationFailure('Sign in to save preferences.');
          }
          await cloud.privacy.apply(settings);
          await cloud.settings.save(settings, expectedUid: uid);
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'Your farm. Your data.',
          'Manage assumptions, saved work, and account preferences.',
        ),
        SectionCard(
          title: 'Farm settings',
          subtitle: farm.name,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => editFarmSettings(context, state),
                icon: const Icon(Icons.tune),
                label: const Text('Model assumptions'),
              ),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        await editModel(
                          context,
                          title: 'Rename farm',
                          initial: {'name': farm.name},
                          validate: (json) => farm
                              .copyWith(name: json['name'] as String)
                              .validate(),
                          onSave: (json) => state.saveFarm(
                            farm.copyWith(name: json['name'] as String),
                          ),
                        );
                      },
                child: const Text('Rename farm'),
              ),
              OutlinedButton.icon(
                onPressed: () => showExport(
                  context,
                  'Farm data export',
                  const FarmExportService().exportFarm(farm),
                ),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export JSON'),
              ),
              OutlinedButton.icon(
                onPressed: state.busy ? null : () => import(context),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import JSON'),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        if (await confirmAction(
                          context,
                          'Delete this farm?',
                          'Delete ${farm.name}, saved runs, scenarios, harvest records, and its published passports? This cannot be undone.',
                        )) {
                          await state.perform(
                            'Deleting farm',
                            () => state.repository!.deleteFarm(farm.id),
                          );
                        }
                      },
                child: const Text('Delete farm'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Saved calculations',
          subtitle:
              'Summaries include inputs and seeds so results can be reproduced.',
          child: Column(
            children: [
              _SavedRuns(
                state: state,
                kind: EntityKind.optimizationRuns,
                label: 'Optimization',
              ),
              _SavedRuns(
                state: state,
                kind: EntityKind.simulationRuns,
                label: 'Simulation',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (cloud != null && privacy != null) ...[
          SectionCard(
            title: 'Privacy preferences',
            subtitle: 'Optional data collection is off until you enable it.',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usage analytics'),
                  subtitle: const Text(
                    'Allow product usage reporting without farm financial payloads.',
                  ),
                  value: privacy.analyticsConsent,
                  onChanged: state.busy
                      ? null
                      : (value) => updatePrivacy(
                          privacy.copyWith(analyticsConsent: value),
                        ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Crash reporting'),
                  subtitle: const Text(
                    'Allow sanitized error types and stack traces.',
                  ),
                  value: privacy.crashReportingConsent,
                  onChanged: state.busy
                      ? null
                      : (value) => updatePrivacy(
                          privacy.copyWith(crashReportingConsent: value),
                        ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cloud assistant'),
                  subtitle: Text(
                    cloud.features.cloudAssistantEnabled
                        ? 'Send your question and a small set of calculated metrics to the configured provider.'
                        : 'Cloud assistant is disabled in this deployment. Local explanations remain available.',
                  ),
                  value: privacy.cloudAssistantConsent,
                  onChanged: state.busy || !cloud.features.cloudAssistantEnabled
                      ? null
                      : (value) => updatePrivacy(
                          privacy.copyWith(cloudAssistantConsent: value),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Account',
            subtitle: cloud.auth.currentUser?.email,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => state.perform('Signing out', cloud.auth.signOut),
                  child: const Text('Sign out'),
                ),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          if (!await confirmAction(
                            context,
                            'Delete your account and data?',
                            'Permanently remove every farm you own, private records, saved runs, published passports, and your account?',
                          )) {
                            return;
                          }
                          if (!context.mounted) return;
                          if (!await showAuth(
                            context,
                            state,
                            reauthenticate: true,
                          )) {
                            return;
                          }
                          if (!context.mounted) return;
                          if (await confirmAction(
                            context,
                            'Complete account deletion?',
                            'Continue with permanent deletion of your account and owned data.',
                          )) {
                            await state.perform(
                              'Deleting account and owned data',
                              cloud.auth.deleteAccount,
                            );
                          }
                        },
                  child: const Text('Delete account and data'),
                ),
              ],
            ),
          ),
        ],
        if (kDebugMode && state.connectivityDiagnostic != null) ...[
          const SizedBox(height: 24),
          SectionCard(
            title: 'Development connectivity check',
            subtitle:
                'Runs only when requested. Creates, reads, and deletes a temporary diagnostics record.',
            child: OutlinedButton.icon(
              onPressed: state.busy ? null : state.runConnectivityDiagnostic,
              icon: const Icon(Icons.network_check),
              label: const Text('Check Firebase connectivity'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const SectionCard(
          title: 'About the model',
          child: Text(
            'FarmTwin uses entered or imported assumptions to calculate farm finances, constrained allocations, risk distributions, and multi-year scenarios. Input provenance is shown with records. Farmer-supplied information is not independently verified. You control what is published in a Harvest Passport.',
          ),
        ),
      ],
    );
  }
}

class _SavedRuns extends StatefulWidget {
  const _SavedRuns({
    required this.state,
    required this.kind,
    required this.label,
  });
  final WorkspaceController state;
  final EntityKind kind;
  final String label;
  @override
  State<_SavedRuns> createState() => _SavedRunsState();
}

class _SavedRunsState extends State<_SavedRuns> {
  late final stream = widget.state.repository!.watchEntities(
    widget.state.farm!.id,
    widget.kind,
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<List<StoredEntity>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Notice(snapshot.error.toString(), error: true);
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      if (snapshot.data!.isEmpty) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${widget.label} runs'),
          subtitle: const Text('No saved runs.'),
        );
      }
      return Column(
        children: snapshot.data!
            .map(
              (entity) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${widget.label} · ${entity.data['createdAt'] ?? entity.id}',
                ),
                subtitle: const Text('Calculated summary with input snapshot'),
                onTap: () => showExport(
                  context,
                  '${widget.label} summary',
                  const JsonEncoder.withIndent('  ').convert(entity.data),
                ),
                trailing: IconButton(
                  tooltip: 'Delete saved run',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirmAction(
                      context,
                      'Delete saved run?',
                      'Remove this stored calculation summary?',
                    )) {
                      await widget.state.perform(
                        'Deleting saved run',
                        () => widget.state.repository!.deleteEntity(
                          widget.state.farm!.id,
                          widget.kind,
                          entity.id,
                        ),
                      );
                    }
                  },
                ),
              ),
            )
            .toList(),
      );
    },
  );
}
