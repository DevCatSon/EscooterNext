import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/ride_screen.dart';
import 'package:escooter_control/ui/widgets.dart';

import 'support/fake_transport.dart';

Widget host(num? value, {bool reduced = false, String unit = 'km/h'}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: AnimatedMetricValue(value, unit: unit)),
      ),
    );

void main() {
  testWidgets(
    'numbers interpolate visually while semantics reports the latest value',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(10));
      expect(find.text('10 km/h', findRichText: true), findsOneWidget);
      await tester.pumpWidget(host(30));
      expect(
        tester.getSemantics(find.byType(AnimatedMetricValue)),
        matchesSemantics(value: '30 km/h'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('20 km/h', findRichText: true), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('30 km/h', findRichText: true), findsOneWidget);
      semantics.dispose();
    },
  );
  testWidgets(
    'Reduce Motion, unknown values and unit changes snap to actual readings',
    (tester) async {
      await tester.pumpWidget(host(10, reduced: true));
      await tester.pumpWidget(host(30, reduced: true));
      expect(find.text('30 km/h', findRichText: true), findsOneWidget);
      await tester.pumpWidget(host(null));
      expect(find.text('— km/h', findRichText: true), findsOneWidget);
      await tester.pumpWidget(host(30));
      expect(find.text('30 km/h', findRichText: true), findsOneWidget);
      await tester.pumpWidget(host(19, unit: 'mph'));
      expect(find.text('19 mph', findRichText: true), findsOneWidget);
    },
  );
  testWidgets(
    'all five dashboard readings animate without mutating reported data',
    (tester) async {
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
      );
      addTearDown(c.dispose);
      await c.startDemo();
      Widget dashboard() => MaterialApp(
        home: Scaffold(body: RideScreen(controller: c)),
      );
      await tester.pumpWidget(dashboard());
      expect(find.byType(AnimatedMetricValue), findsNWidgets(5));
      c.telemetry = c.telemetry.withValues({
        Reading.battery: 50,
        Reading.speed: 30,
        Reading.trip: 9.5,
        Reading.odometer: 901,
        Reading.voltage: 42,
      });
      await tester.pumpWidget(dashboard());
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.telemetry[Reading.battery], 50);
      expect(c.telemetry[Reading.odometer], 901);
      final battery = find.descendant(
        of: find.byKey(const ValueKey('dashboard-battery')),
        matching: find.byType(MetricValue),
      );
      expect(tester.widget<MetricValue>(battery).value, isNot('50'));
      await tester.pumpAndSettle();
      expect(tester.widget<MetricValue>(battery).value, '50');
    },
  );
}
