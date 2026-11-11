import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/app.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets(
    'iOS rename dialog owns its input and lock covers pushed routes',
    (tester) async {
      final controller = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(controller.dispose);
      await controller.startDemo();
      await tester.pumpWidget(
        ScooterApp(controller: controller, platform: TargetPlatform.iOS),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('City runner'));
      await tester.tap(find.text('City runner'));
      await tester.pumpAndSettle();
      expect(find.text('Name your scooter'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Weekend ride');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.scooterName, 'Weekend ride');
      await tester.ensureVisible(find.text('Feature support'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feature support'));
      await tester.pumpAndSettle();
      expect(find.text('Visible controls'), findsOneWidget);
      await controller.toggleLock();
      await tester.pumpAndSettle();
      expect(find.text('Scooter locked'), findsOneWidget);
      await tester.tap(find.text('Unlock scooter'));
      await tester.pumpAndSettle();
      expect(find.text('Scooter locked'), findsNothing);
      expect(find.text('Visible controls'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'welcome enters an isolated demo and all main destinations render',
    (tester) async {
      final transport = FakeTransport();
      final controller = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ScooterApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Try Demo Mode'));
      await tester.tap(find.text('Try Demo Mode'));
      await tester.pumpAndSettle();
      expect(find.text('Kick start'), findsOneWidget);
      expect(find.text('Zero start'), findsNothing);
      expect(find.textContaining('Start mode changes require'), findsNothing);
      expect(find.text('18 km/h', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Tuning'));
      await tester.pumpAndSettle();
      expect(find.text('Speed limit'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      await tester.tap(find.text('31'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apply limit'));
      await tester.tap(find.text('Apply limit'));
      await tester.pumpAndSettle();
      expect(controller.telemetry[Reading.maxSpeed], 31);
      await tester.tap(find.text('Sensors'));
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('About Escooter Next'), 150);
      expect(find.text('About Escooter Next'), findsOneWidget);
      expect(transport.connections, 0);
      expect(transport.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(820, 1180),
    ]) {
      testWidgets(
        'adaptive layout has no overflow on $platform at $size with larger text',
        (tester) async {
          final controller = ScooterController(
            transport: FakeTransport(),
            preferences: MemoryPreferenceStore(),
            permissions: () async {},
          );
          addTearDown(controller.dispose);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await controller.startDemo();
          await tester.pumpWidget(
            ScooterApp(controller: controller, platform: platform),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final destination in [
            'Tuning',
            'Sensors',
            'Settings',
            'Scooter',
          ]) {
            await tester.tap(find.text(destination));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'lock overlay requires confirmed unlock and theme switching preserves navigation',
    (tester) async {
      final controller = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(controller.dispose);
      await controller.startDemo();
      await tester.pumpWidget(ScooterApp(controller: controller));
      await tester.pumpAndSettle();
      await controller.toggleLock();
      await tester.pumpAndSettle();
      expect(find.text('Scooter locked'), findsOneWidget);
      await tester.tap(find.text('Unlock scooter'));
      await tester.pumpAndSettle();
      expect(find.text('Scooter locked'), findsNothing);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await controller.setAppearance(AppAppearance.dark);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('About Escooter Next'), 150);
      expect(find.text('About Escooter Next'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
