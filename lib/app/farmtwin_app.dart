import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/components.dart';
import '../data/data.dart';
import '../features/assistant/assistant_page.dart';
import '../features/auth/auth_dialog.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/farm/farm_page.dart';
import '../features/harvest_passport/harvest_page.dart';
import '../features/optimization/optimization_page.dart';
import '../features/risk/risk_page.dart';
import '../features/scenarios/scenario_page.dart';
import '../features/settings/settings_page.dart';
import '../features/workspace/workspace_controller.dart';
import 'theme/farm_theme.dart';

class FarmTwinApp extends StatefulWidget {
  const FarmTwinApp({super.key, required this.workspace});
  final WorkspaceController workspace;
  @override
  State<FarmTwinApp> createState() => _FarmTwinAppState();
}

class _FarmTwinAppState extends State<FarmTwinApp> {
  late final router = GoRouter(
    initialLocation: '/home',
    routes: [
      for (final path in [
        '/home',
        '/farm',
        '/optimize',
        '/risk',
        '/scenarios',
        '/assistant',
        '/harvest',
        '/settings',
      ])
        GoRoute(
          path: path,
          builder: (context, route) => _WorkspaceShell(
            path: path,
            farmTab: int.tryParse(route.uri.queryParameters['tab'] ?? '') ?? 0,
          ),
        ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [workspaceProvider.overrideWithValue(widget.workspace)],
    child: MaterialApp.router(
      title: 'FarmTwin',
      debugShowCheckedModeBanner: false,
      theme: FarmTheme.light,
      routerConfig: router,
    ),
  );
}

const destinations = <(String, String, IconData)>[
  ('/home', 'Overview', Icons.space_dashboard_outlined),
  ('/farm', 'My farm', Icons.landscape_outlined),
  ('/optimize', 'Optimize', Icons.auto_graph),
  ('/risk', 'Risk & outlook', Icons.show_chart),
  ('/scenarios', 'Scenario lab', Icons.science_outlined),
  ('/assistant', 'Assistant', Icons.chat_bubble_outline),
  ('/harvest', 'Harvest passports', Icons.qr_code_2),
  ('/settings', 'Settings', Icons.settings_outlined),
];

class _WorkspaceShell extends ConsumerWidget {
  const _WorkspaceShell({required this.path, required this.farmTab});
  final String path;
  final int farmTab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= FarmTheme.wide;
        final farm = state.farm;
        Widget navigation({bool drawer = false}) => SizedBox(
          width: 238,
          child: Material(
            color: const Color(0xFFEBEEE5),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(28, 32, 24, 36),
                    child: _Brand(),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      'YOUR WORKSPACE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.7,
                        color: FarmTheme.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: destinations.map((destination) {
                        final selected = destination.$1 == path;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: ListTile(
                            selected: selected,
                            selectedTileColor: FarmTheme.forest,
                            selectedColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            leading: Icon(destination.$3, size: 21),
                            title: Text(
                              destination.$2,
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: state.busy
                                ? null
                                : () {
                                    if (drawer) Navigator.pop(context);
                                    context.go(destination.$1);
                                  },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            state.sampleMode
                                ? Icons.science_outlined
                                : Icons.eco_outlined,
                            color: FarmTheme.moss,
                            size: 22,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.sampleMode
                                ? 'Sample Farm'
                                : 'Farmer-led decisions',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            state.sampleMode
                                ? 'Sample inputs. Live calculations. Saved on this device.'
                                : 'You define the boundaries. Explore what’s possible inside them.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (farm == null) return Scaffold(body: _Welcome(state: state));
        Widget page = switch (path) {
          '/farm' => FarmPage(state: state, initialTab: farmTab),
          '/optimize' => OptimizationPage(state: state),
          '/risk' => RiskPage(state: state),
          '/scenarios' => ScenarioPage(state: state),
          '/assistant' => AssistantPage(
            key: ValueKey('${farm.id}-${state.revision}'),
            state: state,
          ),
          '/harvest' => HarvestPage(key: ValueKey(farm.id), state: state),
          '/settings' => SettingsPage(key: ValueKey(farm.id), state: state),
          _ => DashboardPage(state: state),
        };
        return Scaffold(
          drawer: wide ? null : Drawer(child: navigation(drawer: true)),
          body: Row(
            children: [
              if (wide) navigation(),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: FarmTheme.line),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 36 : 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              if (!wide)
                                Builder(
                                  builder: (context) => IconButton(
                                    tooltip: 'Open navigation',
                                    onPressed: () =>
                                        Scaffold.of(context).openDrawer(),
                                    icon: const Icon(Icons.menu),
                                  ),
                                ),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: farm.id,
                                    isExpanded: true,
                                    items: state.farms
                                        .map(
                                          (f) => DropdownMenuItem(
                                            value: f.id,
                                            child: Text(
                                              f.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: state.busy
                                        ? null
                                        : (id) {
                                            if (id != null) {
                                              state.selectFarm(
                                                state.farms.firstWhere(
                                                  (f) => f.id == id,
                                                ),
                                              );
                                            }
                                          },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (state.sampleMode)
                                const Chip(
                                  label: Text(
                                    'SAMPLE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  avatar: Icon(
                                    Icons.science_outlined,
                                    size: 15,
                                  ),
                                  padding: EdgeInsets.zero,
                                )
                              else
                                StreamBuilder<FarmSyncStatus>(
                                  stream: state.cloud!.farms.syncStatus,
                                  initialData:
                                      state.cloud!.farms.currentSyncStatus,
                                  builder: (context, snapshot) => Tooltip(
                                    message: snapshot.data!.message,
                                    child: Icon(
                                      snapshot.data!.failure != null
                                          ? Icons.cloud_off
                                          : snapshot.data!.hasPendingWrites
                                          ? Icons.cloud_upload_outlined
                                          : snapshot.data!.isFromCache
                                          ? Icons.cloud_off_outlined
                                          : Icons.cloud_done_outlined,
                                      color: snapshot.data!.failure != null
                                          ? FarmTheme.danger
                                          : FarmTheme.moss,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Create farm',
                                onPressed: state.busy
                                    ? null
                                    : () => createFarmDialog(context, state),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (state.busy)
                      Semantics(
                        label: state.busyLabel,
                        liveRegion: true,
                        child: Column(
                          children: [
                            const LinearProgressIndicator(minHeight: 3),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                state.busyLabel ?? 'Working',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!state.sampleMode && state.cloud != null)
                      StreamBuilder<FarmSyncStatus>(
                        stream: state.cloud!.farms.syncStatus,
                        initialData: state.cloud!.farms.currentSyncStatus,
                        builder: (context, snapshot) =>
                            snapshot.data!.failure != null ||
                                snapshot.data!.hasPendingWrites ||
                                snapshot.data!.isFromCache
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                child: Notice(
                                  snapshot.data!.message,
                                  error: snapshot.data!.failure != null,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: PageStorageKey(path),
                        padding: EdgeInsets.all(wide ? 36 : 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (state.error != null ||
                                    state.notice != null) ...[
                                  Notice(
                                    state.error ?? state.notice!,
                                    error: state.error != null,
                                    action: IconButton(
                                      tooltip: 'Dismiss',
                                      onPressed: state.dismissMessage,
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                page,
                              ],
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
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: switch (path) {
                    '/farm' => 1,
                    '/optimize' => 2,
                    '/risk' => 3,
                    '/assistant' => 4,
                    _ => 0,
                  },
                  onDestinationSelected: state.busy
                      ? null
                      : (index) => context.go(
                          [
                            '/home',
                            '/farm',
                            '/optimize',
                            '/risk',
                            '/assistant',
                          ][index],
                        ),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.landscape_outlined),
                      label: 'Farm',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_graph),
                      label: 'Optimize',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.show_chart),
                      label: 'Risk',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      label: 'Assistant',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.grass, color: FarmTheme.forest, size: 30),
      SizedBox(width: 9),
      Flexible(
        child: Text(
          'FarmTwin',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 23,
            letterSpacing: -.7,
            fontWeight: FontWeight.w700,
            color: FarmTheme.forest,
          ),
        ),
      ),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.state});
  final WorkspaceController state;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Brand(),
              const SizedBox(height: 60),
              Text(
                'Your land.\nA clearer outlook.',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 46, height: 1.15),
              ),
              const SizedBox(height: 22),
              const Text(
                'Connect your fields, finances, and operating boundaries. Explore calculated farm plans and understand the tradeoffs before making a decision.',
              ),
              const SizedBox(height: 30),
              if (state.error != null) ...[
                Notice(state.error!, error: true),
                const SizedBox(height: 18),
              ],
              if (state.startupError != null) ...[
                Notice(state.startupError!, error: true),
                const SizedBox(height: 18),
              ],
              if (state.busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 18),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (state.signedIn)
                    FilledButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => createFarmDialog(context, state),
                      icon: const Icon(Icons.add),
                      label: const Text('Create your farm'),
                    )
                  else if (state.cloud != null)
                    FilledButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => showAuth(context, state),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Sign in or create account'),
                    ),
                  OutlinedButton.icon(
                    onPressed: state.busy ? null : state.openSample,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Load Sample Farm'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (state.cloud == null)
                const Notice(
                  'Cloud accounts are not configured in this development build. The explicitly selected Sample Farm works locally, including edits, optimization, simulations, and saved calculations.',
                ),
              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 18),
              const Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Feature(Icons.calculate_outlined, 'Real calculations'),
                  _Feature(Icons.rule, 'Your constraints'),
                  _Feature(Icons.cloud_off_outlined, 'Local analysis'),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: FarmTheme.moss),
      const SizedBox(width: 8),
      Text(text, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
