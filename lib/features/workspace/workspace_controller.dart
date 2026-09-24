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
    required this.cloud,
    this.startupError,
    this.connectivityDiagnostic,
  }) {
    if (cloud != null) {
      _authSubscription = cloud!.auth.authStateChanges.listen(
        (user) {
          if (_disposed) return;
          _restorePrivacy(user?.uid);
          _listen(user == null ? null : cloud!.farms);
          notifyListeners();
        },
        onError: (Object failure) {
          if (_disposed) return;
          _listen(null);
          cloud!.privacy
              .bindAccount(null, () async => const UserSettings())
              .catchError((Object _) {});
          error = 'Authentication could not be confirmed. Sign in again.';
          notifyListeners();
        },
      );
    }
  }
  final FirebaseServices? cloud;
  final String? startupError;
  final Future<String> Function()? connectivityDiagnostic;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<List<Farm>>? _farmsSubscription;
  FirestoreFarmRepository? _repository;
  FirestoreFarmRepository? get repository => _repository;
  List<Farm> farms = [];
  Farm? farm;
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
  RiskComparison? scenarioRisk;
  String? scenarioName;
  int _revision = 0;
  int _workspaceEpoch = 0;
  int _subscriptionEpoch = 0;
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
  String? get setupIssue {
    final value = farm;
    if (value == null) return 'Select or create a farm first.';
    try {
      value.validate(requireReady: true);
      value.validatePlan(value.currentPlan);
      return null;
    } on DomainFailure catch (failure) {
      return '${failure.message} Review the field and crop settings in My farm.';
    }
  }

  bool get ready => farm != null && setupIssue == null;
  FarmFinancialResult? get financial {
    if (!ready) return null;
    try {
      return FinancialEngine().evaluate(farm!, farm!.currentPlan);
    } on DomainFailure {
      return null;
    }
  }

  ConstraintReport? get constraints {
    final result = financial;
    return result == null
        ? null
        : ConstraintEngine().evaluate(farm!, farm!.currentPlan, result);
  }

  void _listen(FirestoreFarmRepository? next) {
    _workspaceEpoch++;
    final subscriptionEpoch = ++_subscriptionEpoch;
    _farmsSubscription?.cancel();
    // Permission errors from the former account (including deletion freezing
    // its live query) do not belong to the newly selected workspace.
    error = null;
    _repository = next;
    farms = [];
    farm = null;
    _invalidate();
    if (next != null) {
      _farmsSubscription = next.watchFarms().listen(
        (values) {
          if (_disposed || subscriptionEpoch != _subscriptionEpoch) return;
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
          if (_disposed || subscriptionEpoch != _subscriptionEpoch) return;
          error = failure.toString();
          notifyListeners();
        },
      );
    }
    notifyListeners();
  }

  void selectFarm(Farm value) {
    _workspaceEpoch++;
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
    scenarioRisk = null;
    scenarioName = null;
  }

  Future<void> saveFarm(Farm value) async {
    final uid = cloud?.auth.currentUser?.uid;
    if (uid == null) {
      throw const AuthenticationFailure('Sign in before saving a farm.');
    }
    final repo = cloud!.farms;
    value.validate();
    final epoch = _workspaceEpoch;
    await repo.saveFarm(value);
    if (cloud!.auth.currentUser?.uid != uid) {
      throw const AuthenticationFailure(
        'Your signed-in account changed. Sign in again to view the saved farm.',
      );
    }
    if (_disposed || epoch != _workspaceEpoch || repository != repo) return;
    farms = [...farms.where((existing) => existing.id != value.id), value];
    farm = value;
    _invalidate();
    notifyListeners();
  }

  Future<void> createFarm({
    String? id,
    required String name,
    required String country,
    required String region,
    required String currencyCode,
    required double declaredAcres,
  }) async {
    if (!signedIn) {
      throw const AuthenticationFailure('Sign in before creating a farm.');
    }
    final settings = FarmSettings.fromJson(
      jsonDecode(
            await rootBundle.loadString('assets/config/default_settings.json'),
          )
          as Map<String, dynamic>,
    );
    final value = Farm(
      id: id ?? const Uuid().v4(),
      name: name.trim(),
      country: country.trim(),
      region: region.trim(),
      declaredAcres: declaredAcres,
      fields: [],
      crops: [],
      expenses: [],
      debts: [],
      constraints: [],
      settings: settings.copyWith(
        currencyCode: currencyCode.trim().toUpperCase(),
      ),
      provenance: Provenance(
        source: DataSourceType.userEntered,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await saveFarm(value);
  }

  Future<void> runConnectivityDiagnostic() => perform(
    'Checking Firebase connectivity',
    () async {
      final diagnostic = connectivityDiagnostic;
      if (!kDebugMode || diagnostic == null) {
        throw const ConfigurationFailure(
          'Connectivity diagnostics are available only in development builds.',
        );
      }
      notice = await diagnostic();
    },
  );

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
        scenarioRisk = null;
        scenarioName = scenario.name;
      });

  Future<void> simulateScenario() async =>
      perform('Simulating scenario uncertainty', () async {
        final snapshot = scenarioFarm;
        final run = scenarioResult;
        if (snapshot == null || run == null) return;
        final revision = _revision;
        final result = await compute(simulateFarm, (
          snapshot,
          run.recommended?.plan,
        ));
        if (revision == _revision && identical(run, scenarioResult)) {
          scenarioRisk = result;
        }
      });

  Future<void> saveRun(bool simulation, {bool scenario = false}) async =>
      perform('Saving calculated summary', () async {
        final savedRisk = scenario ? scenarioRisk : risk;
        final savedOptimization = scenario ? scenarioResult : optimization;
        final result = simulation
            ? <String, dynamic>{
                'current': savedRisk!.current.toJson(),
                if (savedRisk.alternative != null)
                  'alternative': savedRisk.alternative!.toJson(),
              }
            : <String, dynamic>{
                'current': savedOptimization!.current.toJson(),
                'recommended': savedOptimization.recommended?.toJson(),
                'diagnostics': savedOptimization.diagnostics.toJson(),
                'warnings': savedOptimization.warnings,
                'representatives': savedOptimization.representatives.map(
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
              if (scenario) 'scenarioName': scenarioName,
              'input': (scenario ? scenarioFarm! : farm!).toJson(),
              'selectedPlan':
                  (scenario ? scenarioResult!.recommended : selected)?.plan
                      .toJson(),
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
    super.dispose();
  }
}
