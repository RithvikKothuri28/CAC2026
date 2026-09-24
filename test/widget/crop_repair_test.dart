import 'package:farmtwin/app/farmtwin_app.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:farmtwin/features/workspace/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/firebase_workspace.dart';

void main() {
  for (final incomplete in [false, true]) {
    testWidgets(
      incomplete
          ? 'unassigned field stays usable across all screens'
          : 'legacy irrigation mismatch opens repair UI without a red screen',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = fixtureFarm();
        final crop = fixture.crops.first.copyWith(requiresIrrigation: true);
        final field = fixture.fields.first.copyWith(
          name: 'Field 1',
          irrigated: false,
          currentCropId: incomplete ? '' : crop.id,
          compatibleCropIds: incomplete ? [] : [crop.id],
          cropHistory: [],
        );
        final farm = fixture.copyWith(crops: [crop], fields: [field]);
        final cloud = TestCloud(farms: TestFarms([farm]));
        addTearDown(cloud.close);
        final state = WorkspaceController(cloud: cloud);
        addTearDown(state.dispose);
        await tester.pumpWidget(FarmTwinApp(workspace: state));
        await tester.pumpAndSettle();
        expect(state.ready, isFalse);
        expect(state.financial, isNull);
        expect(state.setupIssue, isNotNull);
        if (!incomplete) {
          expect(() => farm.validate(), throwsA(isA<ValidationFailure>()));
        }
        for (final page in [
          'My farm',
          'Optimize',
          'Risk & outlook',
          'Scenario lab',
          'Settings',
          'Overview',
        ]) {
          await tester.tap(find.widgetWithText(ListTile, page));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page);
        }
        await tester.tap(find.widgetWithText(ListTile, 'My farm'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit Field 1'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
