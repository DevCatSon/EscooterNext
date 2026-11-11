import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/app.dart';
import 'package:escooter_control/services/ble_transport.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/motion.dart';
import 'package:escooter_control/ui/widgets.dart';

import 'support/fake_transport.dart';

void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'unfinished naming resumes on launch and fits larger text on a small phone',
    (tester) async {
      phone(tester, size: const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefs = MemoryPreferenceStore();
      await prefs.write(
        'scooter',
        const SavedScooter('resume', 'VC_Test', protocolId: 'vicont').encode(),
      );
      await prefs.write('setupNamePending', 'true');
      await prefs.write('setupSeen', 'true');
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: prefs,
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(c.saved!);
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Name your scooter'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('setup-scooter-name')),
        'City ride',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();
      expect(c.saved!.name, 'City ride');
      expect(find.text('Open dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('fixed landscape dashboard fits regular and double-sized text', (
    tester,
  ) async {
    phone(tester, size: const Size(844, 390));
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await c.startDemo();
    await tester.pumpWidget(ScooterApp(controller: c));
    for (final scale in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clean welcome and setup support double text on a small phone', (
    tester,
  ) async {
    phone(tester, size: const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final transport = FakeTransport();
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      ScooterApp(controller: c, platform: TargetPlatform.iOS),
    );
    await tester.ensureVisible(find.text('Set up scooter'));
    // First launch opens setup automatically.
    await tester.pumpAndSettle();
    expect(find.text('Get ready to connect'), findsOneWidget);
    expect(transport.prepares, 0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close setup'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'dashboard is fixed, modes have distinct colors and temperatures live in Sensors',
    (tester) async {
      phone(tester);
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
      );
      addTearDown(c.dispose);
      await c.startDemo();
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      expect(find.textContaining('temperature'), findsNothing);
      final lockPosition = tester.getTopLeft(find.text('Lock scooter'));
      await tester.drag(
        find.byKey(const ValueKey('fixed-dashboard')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Lock scooter')), lockPosition);
      final colors = [
        for (var gear = 1; gear <= 3; gear++)
          tester
              .widget<TextButton>(find.byKey(ValueKey('gear-$gear')))
              .style!
              .foregroundColor!
              .resolve({}),
      ];
      expect(colors, [
        const Color(0xff16713f),
        const Color(0xff225ac7),
        const Color(0xffbc2835),
      ]);
      await tester.tap(find.text('Eco'));
      await tester.pumpAndSettle();
      expect(c.telemetry.gear, 1);
      await tester.tap(find.text('Sport'));
      await tester.pumpAndSettle();
      expect(c.telemetry.gear, 3);
      await tester.tap(find.text('Sensors'));
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Controller'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'fixed small-screen sections keep all controls reachable at double text size',
    (tester) async {
      phone(tester, size: const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
      );
      addTearDown(c.dispose);
      await c.startDemo();
      await tester.pumpWidget(ScooterApp(controller: c));
      await tester.pumpAndSettle();
      for (final section in [
        'Ride totals',
        'Controls',
        'Ride modes',
        'Lock & find',
        'Overview',
      ]) {
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is DropdownButton),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(section).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'setup asks permission only for discovery and completes after a real connection',
    (tester) async {
      phone(tester);
      final transport = FakeTransport();
      var prompts = 0;
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {
          prompts++;
        },
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        ScooterApp(controller: c, platform: TargetPlatform.iOS),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ScooterArt), findsNothing);
      expect(find.textContaining('Direct Bluetooth'), findsNothing);
      // First launch opens setup automatically.
      await tester.pumpAndSettle();
      expect(find.text('Get ready to connect'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
      expect(prompts, 0);
      expect(transport.prepares, 0);
      await tester.tap(find.text('Find my scooter'));
      await advance(tester);
      expect(prompts, 1);
      expect(find.text('Scooter connected'), findsNothing);
      transport.advertisements.add(
        const NearbyScooter('opaque-ios-uuid', 'VC_Test', -60),
      );
      await tester.pump();
      await tester.tap(find.text('VC_Test'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(
        c.ready,
        isTrue,
        reason:
            '${c.phase}: ${c.message}; connections=${transport.connections}',
      );
      expect(transport.connections, 1);
      expect(find.text('Name your scooter'), findsOneWidget);
      expect(find.text('Open dashboard'), findsNothing);
      expect(c.setupComplete, false);
      await tester.enterText(
        find.byKey(const ValueKey('setup-scooter-name')),
        '   ',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save name'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('setup-scooter-name')),
        '  Morning ride  ',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();
      expect(c.saved!.name, 'Morning ride');
      expect(c.saved!.advertisedName, 'VC_Test');
      expect(c.setupComplete, true);
      expect(find.text('Scooter connected'), findsOneWidget);
      expect(find.text('Open dashboard'), findsOneWidget);
      await tester.tap(find.text('Open dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('Sensors'), findsOneWidget);
      expect(c.saved?.id, 'opaque-ios-uuid');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'closing setup cancels discovery even while authorization is pending',
    (tester) async {
      phone(tester);
      final permission = Completer<void>();
      final transport = FakeTransport();
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () => permission.future,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(ScooterApp(controller: c));
      // First launch opens setup automatically.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my scooter'));
      await advance(tester);
      await tester.tap(find.byTooltip('Close setup'));
      await tester.pumpAndSettle();
      permission.complete();
      await tester.pumpAndSettle();
      expect(c.phase, LinkPhase.idle);
      expect(transport.prepares, 0);
      expect(transport.connections, 0);
      expect(find.text('Add your scooter'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'permission failures stay actionable without showing setup success',
    (tester) async {
      phone(tester);
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
        permissions: () async {
          throw StateError('Allow Bluetooth access in your phone settings.');
        },
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(ScooterApp(controller: c));
      // First launch opens setup automatically.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my scooter'));
      await tester.pumpAndSettle();
      expect(find.text('Search again'), findsOneWidget);
      expect(find.textContaining('Allow Bluetooth access'), findsWidgets);
      expect(find.text('Connection help'), findsOneWidget);
      expect(find.text('Open dashboard'), findsNothing);
      await tester.tap(find.byTooltip('Close setup'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelling an in-flight connection cannot later show success', (
    tester,
  ) async {
    phone(tester);
    final transport = _DelayedTransport();
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(ScooterApp(controller: c));
    // First launch opens setup automatically.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find my scooter'));
    await advance(tester);
    transport.advertisements.add(
      const NearbyScooter('test-id', 'VC_Test', -60),
    );
    await tester.pump();
    await tester.tap(find.text('VC_Test'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await advance(tester);
    expect(
      find.text('Cancel connection'),
      findsOneWidget,
      reason: '${c.phase}: ${c.message}; connections=${transport.connections}',
    );
    await tester.tap(find.text('Cancel connection'));
    await advance(tester);
    transport.gate.complete();
    await tester.pumpAndSettle();
    expect(c.ready, isFalse);
    expect(find.text('Open dashboard'), findsNothing);
    expect(transport.writes, isEmpty);
    await tester.tap(find.byTooltip('Close setup'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reduce Motion removes custom selection animation', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await c.startDemo();
    await tester.pumpWidget(
      ScooterApp(controller: c, platform: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();
    for (final container in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    )) {
      expect(container.duration, Duration.zero);
    }
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      Duration.zero,
    );
    await tester.tap(find.text('Sport'));
    await tester.pump();
    expect(c.telemetry.gear, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Reduce Motion keeps setup state readable without a repeating spinner',
    (tester) async {
      phone(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        ScooterApp(controller: c, platform: TargetPlatform.iOS),
      );
      // First launch opens setup automatically.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my scooter'));
      await tester.pumpAndSettle();
      expect(find.text('Searching nearby…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StateTransition),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('Close setup'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _DelayedTransport extends FakeTransport {
  final gate = Completer<void>();
  @override
  Future<void> connect(
    String id, {
    required BleConnectionProfile profile,
  }) async {
    connections++;
    await gate.future;
  }
}
