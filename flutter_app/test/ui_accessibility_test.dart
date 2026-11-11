import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/app.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/fake_transport.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform controls expose actions and meet touch target sizes',
      (tester) async {
        final controller = ScooterController(
          transport: FakeTransport(),
          preferences: MemoryPreferenceStore(),
        );
        addTearDown(controller.dispose);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await controller.startDemo();
        await tester.pumpWidget(
          ScooterApp(controller: controller, platform: platform),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Kick start')),
          matchesSemantics(
            label: 'Kick start',
            value: 'On',
            isButton: true,
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        await expectLater(
          tester,
          meetsGuideline(
            platform == TargetPlatform.iOS
                ? iOSTapTargetGuideline
                : androidTapTargetGuideline,
          ),
        );
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$platform remains usable with double-sized text in dark mode',
      (tester) async {
        final controller = ScooterController(
          transport: FakeTransport(),
          preferences: MemoryPreferenceStore(),
        );
        addTearDown(controller.dispose);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await controller.startDemo();
        await controller.setAppearance(AppAppearance.dark);
        await tester.pumpWidget(
          ScooterApp(controller: controller, platform: platform),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final tab in ['Tuning', 'Sensors', 'Settings', 'Scooter']) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
