import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/control_rows.dart';
import 'package:escooter_control/app.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets('unit setting waits for the scooter report', (tester) async {
    final transport = FakeTransport();
    final controller = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(controller.dispose);
    await controller.connect(const SavedScooter('test', 'VC_Test'));
    await tester.pumpWidget(ScooterApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Speed & distance'), 150);
    await tester.pumpAndSettle();
    expect(find.text('Not reported'), findsOneWidget);
    transport.status();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Speed & distance'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Miles · mph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miles · mph'));
    await tester.pump();
    expect(controller.pending(ScooterControl.unit), isTrue);
    expect(controller.telemetry.miles, isFalse);
    expect(find.text('Updating…'), findsOneWidget);
    transport.status(flags: 0x83);
    await tester.pumpAndSettle();
    expect(find.text('mph · mi'), findsOneWidget);
    expect(controller.telemetry.miles, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'both unit selectors support large text without demo BLE writes',
    (tester) async {
      final transport = FakeTransport();
      final controller = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(controller.dispose);
      await controller.startDemo();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await controller.setAppearance(AppAppearance.dark);
      await tester.pumpWidget(ScooterApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Speed & distance'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speed & distance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Miles · mph'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miles · mph'));
      await tester.pumpAndSettle();
      expect(controller.telemetry.miles, isTrue);
      await tester.scrollUntilVisible(find.text('Temperature'), 100);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Temperature'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fahrenheit · °F'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fahrenheit · °F'));
      await tester.pumpAndSettle();
      expect(controller.fahrenheit, isTrue);
      expect(transport.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('switch row exposes one labelled toggle with a full row target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    bool? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ControlSwitchRow(
            label: 'Light',
            value: false,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Light'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Light')),
      matchesSemantics(
        label: 'Light',
        hasToggledState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSize(find.byType(ControlSwitchRow)).height,
      greaterThanOrEqualTo(84),
    );
    await tester.tap(find.text('Light'));
    expect(selected, true);
    semantics.dispose();
  });
}
