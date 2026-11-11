import 'package:escooter_control/app.dart';
import 'package:escooter_control/catalog/scooter_catalog.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/scooter_models_screen.dart';
import 'package:escooter_control/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets(
    'saving a local model changes the menu identity and dashboard artwork',
    (tester) async {
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('a', 'VC_Test'));
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scooter models'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scooter models'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save this model'));
      await tester.tap(find.text('Save this model'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My commuter');
      await tester.tap(find.text('Scooter symbol'));
      await tester.pump();
      await tester.tap(find.text('Save model'));
      await tester.pumpAndSettle();
      expect(c.modelLabel, 'My commuter');
      expect(c.artwork, 'icon:scooter');
      expect(find.text('My commuter'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scooter').last);
      await tester.pumpAndSettle();
      expect(find.text('My commuter'), findsOneWidget);
      expect(
        tester.widget<ScooterArt>(find.byType(ScooterArt)).artwork,
        'icon:scooter',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform model library and save dialog fit small screens with large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = ScooterController(
          transport: FakeTransport(),
          preferences: MemoryPreferenceStore(),
          permissions: () async {},
        );
        addTearDown(c.dispose);
        await c.connect(const SavedScooter('a', 'VC_Test'));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ScooterModelsScreen(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -480));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save this model'));
        await tester.pumpAndSettle();
        expect(find.text('Save scooter model'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('missing catalogue artwork falls back to a scooter symbol', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScooterArt(artwork: 'assets/not-present.png')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.electric_scooter_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'model defaults update visible controls when firmware identifies a model',
    (tester) async {
      final t = FakeTransport();
      final c = ScooterController(
        transport: t,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        catalog: ScooterCatalog([
          const ScooterModel(
            id: 'fixture',
            name: 'Fixture commuter',
            protocolId: 'vicont',
            firmware: {'controllerHardware': 2},
            features: {Feature.headlight},
            artwork: 'icon:scooter',
          ),
        ]),
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('a', 'VC_Test'));
      t.status();
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Kick start'), findsOneWidget);
      t.emit(18, [0, 0, 3, 18, 0, 0, 2, 27, 7]);
      await tester.pumpAndSettle();
      expect(find.text('Fixture commuter'), findsOneWidget);
      expect(find.text('Headlight'), findsOneWidget);
      expect(find.text('Kick start'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
