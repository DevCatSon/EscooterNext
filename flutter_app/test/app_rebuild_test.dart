import 'package:escooter_control/app.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets('app listeners follow a replacement injected controller', (
    tester,
  ) async {
    ScooterController controller() => ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    final first = controller();
    final second = controller();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.startDemo();
    await second.startDemo();
    await first.setAppearance(AppAppearance.dark);
    await second.setAppearance(AppAppearance.light);
    await tester.pumpWidget(ScooterApp(controller: first));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ScooterApp(controller: second));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    await first.setAppearance(AppAppearance.system);
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(app));
    await second.setAppearance(AppAppearance.dark);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'telemetry updates the dashboard without rebuilding MaterialApp',
    (tester) async {
      final transport = FakeTransport();
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await c.connect(const SavedScooter('test', 'VC_Test'));
      transport.status();
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      for (final speed in [120, 180, 230]) {
        transport.emit(16, [0x12, 0xfc, 0, 0, 0, speed, 82]);
        await tester.pump(const Duration(milliseconds: 120));
        // The dashboard animates the numeric change after the telemetry update.
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text('${speed ~/ 10} km/h', findRichText: true),
          findsOneWidget,
        );
        expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(app));
        expect(
          tester.state<NavigatorState>(find.byType(Navigator)),
          same(navigator),
        );
      }
      await c.setAppearance(AppAppearance.dark);
      await tester.pumpAndSettle();
      final themed = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(themed.themeMode, ThemeMode.dark);
      expect(themed, isNot(same(app)));
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      // A lock reported by the scooter itself bypasses the telemetry throttle.
      transport.status(second: 3);
      await tester.pump();
      expect(find.text('Scooter locked'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)),
        same(themed),
      );
      transport.status(second: 1);
      await tester.pumpAndSettle();
      expect(find.text('Scooter locked'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
