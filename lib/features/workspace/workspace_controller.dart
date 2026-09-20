import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/data.dart';
import '../../domain/farm_domain.dart';

final workspaceProvider = Provider<WorkspaceController>(
  (ref) => throw StateError('Workspace not initialized'),
);

class RiskComparison {
  const RiskComparison(this.current, this.alternative);
  final MonteCarloResult current;
  final MonteCarloResult? alternative;
}

OptimizationResult optimizeFarm(Farm farm) => OptimizationEngine().run(farm);
RiskComparison simulateFarm((Farm, FarmPlan?) input) {
  final (farm, alternative) = input;
  final engine = MonteCarloEngine();
  return RiskComparison(
    engine.run(farm, farm.currentPlan),
    alternative == null ? null : engine.run(farm, alternative),
  );
}

MultiYearComparison projectFarm((Farm, FarmPlan) input) =>
    MultiYearEngine().compare(input.$1, input.$1.currentPlan, input.$2);

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.sampleRepository,
    required this.cloud,
    this.startupError,
  }) {
    if (cloud != null) {
      _authSubscription = cloud!.auth.authStateChanges.listen((user) {
        _restorePrivacy(user?.uid);
        if (!sampleMode) {
          _listen(user == null ? null : cloud!.farms);
        }
        notifyListeners();
      });
    }
  }
  final SampleFarmRepository sampleRepository;
  final FirebaseServices? cloud;
  final String? startupError;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<List<Farm>>? _farmsSubscription;
  FarmRepository? repository;
  List<Farm> farms = [];
  Farm? farm;
  bool sampleMode = false;
  bool busy = false;
  String? busyLabel;
  String? error;
  String? notice;
  OptimizationResult? optimization;
  EvaluatedPlan? selected;
  RiskComparison? risk;
  MultiYearComparison? projection;
  Farm? scenarioFarm;
  OptimizationResult? scenarioResult;
  String? scenarioName;
  int _revision = 0;
  int get revision => _revision;
  bool _disposed = false;
  Future<void> _restorePrivacy(String? uid) async {
    try {
      await cloud!.privacy.bindAccount(uid, cloud!.settings.read);
    } catch (_) {
      if (!_disposed && signedIn) {
        notice =
            'Cloud privacy preferences could not be refreshed. Only preferences saved for this account on this device are used.';
      }
    }
    if (!_disposed) notifyListeners();
  }

  bool get signedIn => cloud?.auth.currentUser != null;
  bool get ready =>
      farm != null && farm!.fields.isNotEmpty && farm!.crops.isNotEmpty;
  FarmFinancialResult? get financial =>
      ready ? FinancialEngine().evaluate(farm!, farm!.currentPlan) : null;
  ConstraintReport? get constraints => ready
      ? ConstraintEngine().evaluate(farm!, farm!.currentPlan, financial!)
      : null;

  void _listen(FarmRepository? next) {
    _farmsSubscription?.cancel();
    repository = next;
    farms = [];
    farm = null;
    _invalidate();
    if (next != null) {
      _farmsSubscription = next.watchFarms().listen(
        (values) {
          farms = values;
          final matching = values.where((value) => value.id == farm?.id);
          final updated = matching.isNotEmpty
              ? matching.first
              : (values.isEmpty ? null : values.first);
          if (jsonEncode(updated?.toJson()) != jsonEncode(farm?.toJson())) {
            farm = updated;
            _invalidate();
          }
          notifyListeners();
        },
        onError: (Object failure) {
          error = failure.toString();
          notifyListeners();
        },
      );
    }
    notifyListeners();
  }

  Future<void> openSample({bool reset = false}) async {
    await perform('Loading Sample Farm', () async {
      sampleMode = true;
      _listen(sampleRepository);
      final stored = await sampleRepository.watchFarms().first;
      final loaded = reset || stored.isEmpty
          ? await sampleRepository.loadSample()
          : stored.first;
      farms = await sampleRepository.watchFarms().first;
      farm = loaded;
      _invalidate();
    });
  }

  void leaveSample() {
    sampleMode = false;
    _listen(signedIn ? cloud!.farms : null);
  }

  void selectFarm(Farm value) {
    farm = value;
    _invalidate();
    notifyListeners();
  }

  void _invalidate() {
    _revision++;
    optimization = null;
    selected = null;
    risk = null;
    projection = null;
    scenarioFarm = null;
    scenarioResult = null;
    scenarioName = null;
  }

  Future<void> saveFarm(Farm value) async {
    value.validate();
    final repo = repository;
    if (repo == null) throw StateError('Sign in before saving a farm.');
    await repo.saveFarm(value);
    farm = value;
    _invalidate();
    notifyListeners();
  }

  Future<void> createFarm(String name) async {
    final settings = FarmSettings.fromJson(
      jsonDecode(
            await rootBundle.loadString('assets/config/default_settings.json'),
          )
          as Map<String, dynamic>,
    );
    final value = Farm(
      id: const Uuid().v4(),
      name: name.trim(),
      fields: [],
      crops: [],
      expenses: [],
      debts: [],
      constraints: [],
      settings: settings,
      provenance: Provenance(
        source: DataSourceType.userEntered,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await saveFarm(value);
  }

  Future<void> optimize() async => perform('Evaluating farm plans', () async {
    final snapshot = farm!;
    final revision = _revision;
    snapshot.validate(requireReady: true);
    final result = await compute(optimizeFarm, snapshot);
    if (revision != _revision) return;
    optimization = result;
    selected = result.recommended;
    risk = null;
    projection = null;
  });

  void selectPlan(EvaluatedPlan value) {
    _revision++;
    selected = value;
    risk = null;
    projection = null;
    notifyListeners();
  }

  Future<void> simulate() async =>
      perform('Sampling yield, price, and cost uncertainty', () async {
        final revision = _revision;
        final result = await compute(simulateFarm, (farm!, selected?.plan));
        if (revision == _revision) risk = result;
      });

  Future<void> project() async =>
      perform('Projecting rotation, inflation, and debt', () async {
        final revision = _revision;
        final result = await compute(projectFarm, (
          farm!,
          selected?.plan ?? farm!.currentPlan,
        ));
        if (revision == _revision) projection = result;
      });

  Future<void> runScenario(StressScenario scenario) async =>
      perform('Re-optimizing scenario', () async {
        final revision = _revision;
        final modified = ScenarioEngine().apply(farm!, scenario);
        final result = await compute(optimizeFarm, modified);
        if (revision != _revision) return;
        scenarioFarm = modified;
        scenarioResult = result;
        scenarioName = scenario.name;
      });

  Future<void> saveRun(bool simulation) async =>
      perform('Saving calculated summary', () async {
        final result = simulation
            ? <String, dynamic>{
                'current': risk!.current.toJson(),
                if (risk!.alternative != null)
                  'alternative': risk!.alternative!.toJson(),
              }
            : <String, dynamic>{
                'current': optimization!.current.toJson(),
                'recommended': optimization!.recommended?.toJson(),
                'diagnostics': optimization!.diagnostics.toJson(),
                'warnings': optimization!.warnings,
                'representatives': optimization!.representatives.map(
                  (key, value) => MapEntry(key, value.toJson()),
                ),
              };
        await repository!.saveEntity(
          farm!.id,
          simulation ? EntityKind.simulationRuns : EntityKind.optimizationRuns,
          StoredEntity(
            id: const Uuid().v4(),
            data: {
              'schemaVersion': 1,
              'createdAt': DateTime.now().toUtc().toIso8601String(),
              'input': farm!.toJson(),
              'selectedPlan': selected?.plan.toJson(),
              'result': result,
            },
          ),
        );
        notice = 'Summary and reproducible inputs saved.';
      });

  Future<void> applySelected() async {
    final plan = selected!.plan;
    await saveFarm(
      farm!.copyWith(
        fields: farm!.fields
            .map(
              (field) =>
                  field.copyWith(currentCropId: plan.assignments[field.id]!),
            )
            .toList(),
      ),
    );
  }

  Future<void> perform(String label, Future<void> Function() task) async {
    if (busy) return;
    busy = true;
    busyLabel = label;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await task();
    } catch (failure) {
      error = failure.toString();
    } finally {
      busy = false;
      busyLabel = null;
      if (!_disposed) notifyListeners();
    }
  }

  void dismissMessage() {
    error = null;
    notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _authSubscription?.cancel();
    _farmsSubscription?.cancel();
    sampleRepository.close();
    super.dispose();
  }
}
