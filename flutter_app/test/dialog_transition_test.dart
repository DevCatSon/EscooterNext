import 'dart:ui' as ui;

import 'package:escooter_control/app.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/dialogs.dart';
import 'package:escooter_control/ui/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets(
    'the gradient stays unchanged while opening and exiting Demo connection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
      );
      addTearDown(c.dispose);
      await c.startDemo();
      await c.setAppearance(AppAppearance.dark);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ScooterApp(controller: c, platform: TargetPlatform.android),
        ),
      );
      await tester.pumpAndSettle();

      Future<List<int>> backgroundPixel() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = (await tester.runAsync(
          () => render.toImage(pixelRatio: 1),
        ))!;
        final bytes = (await tester.runAsync(
          () => picture.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        // This corner remains outside the sliding page's text and buttons.
        final offset = (100 * picture.width + picture.width - 3) * 4;
        final rgba = bytes.buffer.asUint8List().sublist(offset, offset + 4);
        picture.dispose();
        return rgba;
      }

      final background = await backgroundPixel();
      await tester.tap(find.byTooltip('Connection details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(await backgroundPixel(), background);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit Demo Mode'));
      await tester.pump();
      for (final milliseconds in [16, 70, 100, 160]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        expect(await backgroundPixel(), background);
        expect(find.text('Disconnected'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.text('Add your scooter'), findsOneWidget);
      expect(c.isDemo, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'popup motion respects Reduce Motion = $reduced and selected units stay visible',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final transport = FakeTransport();
        final prefs = MemoryPreferenceStore();
        final c = ScooterController(transport: transport, preferences: prefs);
        addTearDown(c.dispose);
        await c.startDemo();
        await tester.pumpWidget(
          ScooterApp(controller: c, platform: TargetPlatform.iOS),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Temperature'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Temperature'));
        await tester.pumpAndSettle();
        final picker = find.byType(AppChoiceDialog<bool>);
        final route = ModalRoute.of(tester.element(picker))!;
        expect(
          route.transitionDuration,
          reduced ? Duration.zero : AppMotion.popup,
        );
        expect(
          find.ancestor(of: picker, matching: find.byType(ScaleTransition)),
          reduced ? findsNothing : findsOneWidget,
        );
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
        expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
        expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
        final primary = Theme.of(tester.element(picker)).colorScheme.primary;
        for (final icon in [
          Icons.thermostat_rounded,
          Icons.ac_unit_rounded,
          Icons.wb_sunny_outlined,
          Icons.check_circle_rounded,
        ]) {
          expect(tester.widget<Icon>(find.byIcon(icon)).color, primary);
        }
        for (final container in tester.widgetList<AnimatedContainer>(
          find.descendant(of: picker, matching: find.byType(AnimatedContainer)),
        )) {
          expect(
            container.duration,
            reduced ? Duration.zero : AppMotion.feedback,
          );
        }
        await tester.tap(find.text('Fahrenheit · °F'));
        await tester.pumpAndSettle();
        expect(c.fahrenheit, isTrue);
        expect(prefs.read('temperatureUnit'), 'fahrenheit');
        expect(transport.writes, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
