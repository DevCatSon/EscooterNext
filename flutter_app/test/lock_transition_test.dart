import 'package:escooter_control/app.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/locked_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final reduced in [false, true]) {
      testWidgets(
        '$platform lock motion waits for reports and blocks routes; reduced=$reduced',
        (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final transport = FakeTransport();
          final c = ScooterController(
            transport: transport,
            preferences: MemoryPreferenceStore(),
            permissions: () async {},
          );
          addTearDown(c.dispose);
          await c.connect(const SavedScooter('test', 'VC_Test'));
          transport.status();
          // A write acknowledgement alone must never present success.
          transport.onWrite = (data) {
            if (data.length > 6 && data[4] == 51) {
              transport.emit(51, [data[6]]);
            }
          };
          await tester.pumpWidget(
            ScooterApp(controller: c, platform: platform),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Feature support'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Feature support'));
          await tester.pumpAndSettle();

          final lock = c.toggleLock();
          await tester.pump(const Duration(milliseconds: 80));
          expect(c.pending(ScooterControl.lock), isTrue);
          expect(find.byType(LockedPanel), findsNothing);
          transport.status(second: 3);
          await tester.pump();
          expect(await lock, isTrue);
          expect(find.text('Scooter locked'), findsOneWidget);
          final fade = find.byKey(const ValueKey('scooter-lock-fade'));
          double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
          expect(opacity(), reduced ? 1 : 0);
          // Even the first, transparent animation frame intercepts route touches.
          final back = find.byTooltip('Back');
          await tester.tap(back, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Visible controls'), findsOneWidget);
          if (!reduced) expect(opacity(), allOf(greaterThan(0), lessThan(1)));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Unlock scooter'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(c.pending(ScooterControl.lock), isTrue);
          expect(find.text('Waiting for scooter…'), findsOneWidget);
          expect(find.text('Scooter locked'), findsOneWidget);
          expect(opacity(), 1);
          transport.status(second: 1);
          await tester.pump();
          expect(c.telemetry.locked, isFalse);
          if (reduced) {
            expect(find.byType(LockedPanel), findsNothing);
          } else {
            expect(find.text('Scooter unlocked'), findsOneWidget);
            await tester.pump(const Duration(milliseconds: 100));
            expect(opacity(), allOf(greaterThan(0), lessThan(1)));
            final panel = find.byType(LockedPanel);
            expect(
              tester
                  .widget<IgnorePointer>(
                    find
                        .ancestor(
                          of: panel,
                          matching: find.byType(IgnorePointer),
                        )
                        .first,
                  )
                  .ignoring,
              isTrue,
            );
            final unlockButton = find.descendant(
              of: panel,
              matching: find.byType(FilledButton),
            );
            expect(tester.widget<FilledButton>(unlockButton).onPressed, isNull);
          }
          await tester.pumpAndSettle();
          expect(find.byType(LockedPanel), findsNothing);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.text('Visible controls'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('disconnect removes a partially visible lock panel immediately', (
    tester,
  ) async {
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await c.startDemo();
    await tester.pumpWidget(ScooterApp(controller: c));
    await tester.pumpAndSettle();
    await c.toggleLock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LockedPanel), findsOneWidget);
    await c.disconnect();
    await tester.pump();
    expect(find.byType(LockedPanel), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Add your scooter'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
