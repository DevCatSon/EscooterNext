import 'package:escooter_control/app.dart';
import 'package:escooter_control/core/display_units.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/control_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets(
    'expansion states and scroll offset remain separate when returning to Sensors',
    (tester) async {
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
      );
      addTearDown(c.dispose);
      await c.startDemo();
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sensors'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Battery pack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Battery pack'));
      await tester.pumpAndSettle();
      expect(find.text('Charge cycles'), findsOneWidget);
      await tester.tap(find.text('Tuning'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sensors'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Charge cycles'), findsOneWidget);
      await tester.ensureVisible(find.text('Motor & brake signals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motor & brake signals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sensors'));
      await tester.pumpAndSettle();
      expect(find.text('Throttle · raw'), findsOneWidget);
      expect(find.text('Charge cycles'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('exiting demo from Settings returns to the connection home', (
    tester,
  ) async {
    final transport = FakeTransport();
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await c.startDemo();
    await tester.pumpWidget(ScooterApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Control'), findsNothing);
    await tester.tap(find.text('Exit Demo Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Add your scooter'), findsOneWidget);
    expect(find.text('Scooter models'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(transport.connections, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'first launch presents setup once without Bluetooth or completing it through demo',
    (tester) async {
      final prefs = MemoryPreferenceStore();
      final transport = FakeTransport();
      final c = ScooterController(transport: transport, preferences: prefs);
      addTearDown(c.dispose);
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Get ready to connect'), findsOneWidget);
      expect(transport.prepares, 0);
      await tester.tap(find.text('Try Demo Mode'));
      await tester.pumpAndSettle();
      expect(c.isDemo, isTrue);
      expect(c.setupComplete, isFalse);
      expect(prefs.read('setupSeen'), 'true');
      expect(prefs.read('scooter'), isNull);
      await tester.pumpWidget(const SizedBox());
      final next = ScooterController(
        transport: FakeTransport(),
        preferences: prefs,
      );
      addTearDown(next.dispose);
      await tester.pumpWidget(ScooterApp(controller: next));
      await tester.pumpAndSettle();
      expect(find.text('Get ready to connect'), findsNothing);
      expect(find.text('Add your scooter'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'selected modes retain their icons and the app has a gradient backdrop',
    (tester) async {
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
      );
      addTearDown(c.dispose);
      await c.startDemo();
      await c.setAppearance(AppAppearance.dark);
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      final background = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('app-gradient')),
      );
      expect(
        (background.decoration as BoxDecoration).gradient,
        isA<LinearGradient>(),
      );
      for (final (mode, icon) in [
        (1, Icons.eco_outlined),
        (2, Icons.electric_scooter_outlined),
        (3, Icons.bolt_outlined),
      ]) {
        await c.setGear(mode);
        await tester.pumpAndSettle();
        final button = find.byKey(ValueKey('gear-$mode'));
        expect(
          find.descendant(of: button, matching: find.byIcon(icon)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: button,
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsNothing,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('temperature display converts only known Celsius readings and persists locally', () async {
    final transport = FakeTransport();
    final prefs = MemoryPreferenceStore();
    final c = ScooterController(transport: transport, preferences: prefs);
    addTearDown(c.dispose);
    await c.startDemo();
    await c.setFahrenheit(true);
    expect(DisplayUnits.temperature(0, true), 32);
    expect(DisplayUnits.temperature(100, true), 212);
    expect(DisplayUnits.temperature(-40, true), -40);
    expect(DisplayUnits.temperatureText(null, true), '—');
    expect(c.telemetry[Reading.controllerTemp], 34);
    expect(c.telemetry[Reading.bmsTemperature], 30);
    expect(transport.writes, isEmpty);
    final next = ScooterController(
      transport: FakeTransport(),
      preferences: prefs,
    );
    addTearDown(next.dispose);
    expect(next.fahrenheit, isTrue);
  });

  testWidgets('Sensors shows Fahrenheit while BMS temperature stays raw', (
    tester,
  ) async {
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await c.startDemo();
    await c.setFahrenheit(true);
    await tester.pumpWidget(ScooterApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sensors'));
    await tester.pumpAndSettle();
    expect(find.text('93 °F', findRichText: true), findsOneWidget);
    expect(find.text('102 °F', findRichText: true), findsOneWidget);
    expect(find.text('86 °F', findRichText: true), findsOneWidget);
    expect(find.byType(ControlValueRow), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
