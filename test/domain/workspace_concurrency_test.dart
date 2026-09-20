import 'dart:async';
import 'dart:io';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedSaveRepository extends Fake implements FarmRepository {
  final saved = Completer<void>();
  @override
  Future<void> saveFarm(Farm farm) => saved.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<WorkspaceController> workspace() async {
    final repository = await SampleFarmRepository.open(
      loadAsset: (path) async => File(path).readAsStringSync(),
    );
    final state = WorkspaceController(
      sampleRepository: repository,
      cloud: null,
    );
    await state.openSample();
    await state.optimize();
    expect(state.error, isNull);
    expect(state.optimization, isNotNull);
    return state;
  }

  test(
    'selection change invalidates a real in-flight simulation result',
    () async {
      final state = await workspace();
      addTearDown(state.dispose);
      final pending = state.simulate();
      expect(state.busy, isTrue);
      final revision = state.revision;
      state.selectPlan(state.optimization!.current);
      expect(state.revision, greaterThan(revision));
      await pending;
      expect(state.error, isNull);
      expect(
        state.risk,
        isNull,
        reason: 'The completed simulation belongs to the former selection.',
      );
      await state.simulate();
      expect(state.risk, isNotNull);
      expect(state.risk!.current.samples, state.risk!.alternative!.samples);
    },
  );

  test(
    'disposed workspace cannot publish a completed background computation',
    () async {
      final state = await workspace();
      final pending = state.simulate();
      state.dispose();
      await pending;
      expect(state.risk, isNull);
    },
  );

  test(
    'completed save cannot restore a farm after leaving its workspace',
    () async {
      final state = await workspace();
      addTearDown(state.dispose);
      final delayed = _DelayedSaveRepository();
      state.repository = delayed;
      final pending = state.saveFarm(
        state.farm!.copyWith(name: 'Pending edit'),
      );
      state.leaveSample();
      expect(state.farm, isNull);
      delayed.saved.complete();
      await pending;
      expect(state.farm, isNull);
      expect(state.repository, isNull);
    },
  );

  test('completed save cannot replace a newly selected farm', () async {
    final state = await workspace();
    addTearDown(state.dispose);
    final delayed = _DelayedSaveRepository();
    state.repository = delayed;
    final pending = state.saveFarm(state.farm!.copyWith(name: 'Pending edit'));
    final selected = state.farm!.copyWith(
      id: 'another-farm',
      name: 'Another farm',
    );
    state.selectFarm(selected);
    delayed.saved.complete();
    await pending;
    expect(state.farm!.id, selected.id);
    expect(state.farm!.name, selected.name);
  });
}
