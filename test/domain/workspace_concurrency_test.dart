import 'dart:async';
import 'package:farmtwin/data/data.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/firebase_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<WorkspaceController> workspace() async {
    final cloud = TestCloud(farms: TestFarms([fixtureFarm()]));
    addTearDown(cloud.close);
    final state = WorkspaceController(cloud: cloud);
    await Future<void>.delayed(Duration.zero);
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
      final delayed = (state.cloud as TestCloud).farms;
      delayed.acknowledgement = Completer<void>();
      final pending = state.saveFarm(
        state.farm!.copyWith(name: 'Pending edit'),
      );
      await state.cloud!.auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(state.farm, isNull);
      delayed.acknowledgement!.complete();
      await expectLater(pending, throwsA(isA<AuthenticationFailure>()));
      expect(state.farm, isNull);
      expect(state.repository, isNull);
    },
  );

  test('completed save cannot replace a newly selected farm', () async {
    final state = await workspace();
    addTearDown(state.dispose);
    final delayed = (state.cloud as TestCloud).farms;
    delayed.acknowledgement = Completer<void>();
    final pending = state.saveFarm(state.farm!.copyWith(name: 'Pending edit'));
    final selected = state.farm!.copyWith(
      id: 'another-farm',
      name: 'Another farm',
    );
    delayed.values = [...delayed.values, selected];
    state.selectFarm(selected);
    delayed.acknowledgement!.complete();
    await pending;
    expect(state.farm!.id, selected.id);
    expect(state.farm!.name, selected.name);
  });
}
