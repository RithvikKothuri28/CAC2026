import 'dart:async';

import 'package:farmtwin/core/errors/app_failure.dart';
import 'package:farmtwin/domain/farm_domain.dart';
import 'package:farmtwin/features/farm/field_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/firebase_workspace.dart';

Future<void> openEditor(
  WidgetTester tester, {
  required Farm farm,
  Field? field,
  required Future<void> Function(Field) save,
}) async {
  tester.view.physicalSize = const Size(1100, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showFieldEditor(
              context,
              farm: farm,
              field: field,
              onSave: save,
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

DropdownButton<String> currentSelector(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('field-current-crop')),
        matching: find.byType(DropdownButton<String>),
      ),
    );

Future<void> enterRequired(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Field 1');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Area (acres)'),
    '12.5',
  );
}

void main() {
  testWidgets(
    'new field without crop profiles saves an unassigned draft without crashing',
    (tester) async {
      Field? saved;
      await openEditor(
        tester,
        farm: fixtureFarm().copyWith(fields: [], crops: []),
        save: (field) async => saved = field,
      );
      expect(find.textContaining('No crop profiles yet.'), findsOneWidget);
      expect(
        find.textContaining('No compatible crops selected.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await enterRequired(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.currentCropId, isEmpty);
      expect(saved!.compatibleCropIds, isEmpty);
      expect(saved!.irrigated, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current crop choices require explicit stable IDs and field irrigation',
    (tester) async {
      final corn = fixtureFarm().crops.first.copyWith(id: 'crop-uuid-1');
      final soy = fixtureFarm().crops[1].copyWith(id: 'crop-uuid-2');
      Field? saved;
      await openEditor(
        tester,
        farm: fixtureFarm().copyWith(fields: [], crops: [corn, soy]),
        save: (field) async => saved = field,
      );
      expect(currentSelector(tester).items!.map((item) => item.value), ['']);
      await tester.tap(find.byKey(ValueKey('field-compatible-${corn.id}')));
      await tester.pumpAndSettle();
      expect(currentSelector(tester).items!.map((item) => item.value), ['']);
      await tester.tap(find.byKey(ValueKey('field-compatible-${soy.id}')));
      await tester.pumpAndSettle();
      expect(currentSelector(tester).items!.map((item) => item.value), [
        '',
        soy.id,
      ]);
      await tester.tap(find.byKey(const ValueKey('field-irrigated')));
      await tester.pumpAndSettle();
      expect(currentSelector(tester).items!.map((item) => item.value), [
        '',
        corn.id,
        soy.id,
      ]);
      // A display name is never used as a dropdown value or saved reference.
      currentSelector(tester).onChanged!(corn.id);
      await tester.pumpAndSettle();
      await enterRequired(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.currentCropId, corn.id);
      expect(saved!.compatibleCropIds, [corn.id, soy.id]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing current crop compatibility requires an explicit replacement before save',
    (tester) async {
      final farm = fixtureFarm();
      var saves = 0;
      Field? saved;
      final field = farm.fields.first.copyWith(compatibleCropIds: ['corn']);
      await openEditor(
        tester,
        farm: farm.copyWith(fields: [field]),
        field: field,
        save: (value) async {
          saves++;
          saved = value;
        },
      );
      await tester.tap(find.byKey(const ValueKey('field-compatible-corn')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The current crop is not compatible'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      currentSelector(tester).onChanged!('');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(saved!.currentCropId, isEmpty);
      expect(saved!.compatibleCropIds, isEmpty);
    },
  );

  testWidgets(
    'unknown legacy current crop displays validation without a dropdown assertion',
    (tester) async {
      final farm = fixtureFarm();
      final field = farm.fields.first.copyWith(
        currentCropId: 'missing-profile-id',
      );
      var saves = 0;
      await openEditor(
        tester,
        farm: farm.copyWith(fields: [field]),
        field: field,
        save: (_) async => saves++,
      );
      expect(
        find.textContaining('The current crop is not compatible'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'field save awaits acknowledgement and preserves entered choices on failure',
    (tester) async {
      final acknowledgement = Completer<void>();
      await openEditor(
        tester,
        farm: fixtureFarm().copyWith(fields: []),
        save: (_) async {
          await acknowledgement.future;
          throw const PermissionFailure(
            'Permission denied while saving this field.',
          );
        },
      );
      await enterRequired(tester);
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      acknowledgement.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Permission denied while saving this field.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Field 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
