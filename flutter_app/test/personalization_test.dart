import 'package:escooter_control/app.dart';
import 'package:escooter_control/services/app_icons.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:escooter_control/ui/personalization_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

class FakeIcons extends AppIconService {
  String name = 'standard';
  bool fail = false, canChange = true;
  @override
  Future<Map<Object?, Object?>> capabilities() async => {
    'name': name,
    'canChange': canChange,
  };
  @override
  Future<void> select(AppIconPreset preset) async {
    if (fail) throw StateError('OS rejected selection');
    name = preset.name;
  }
}

Future<void> icons(
  WidgetTester tester,
  FakeIcons service, {
  bool ios = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: ios ? TargetPlatform.iOS : TargetPlatform.android,
      ),
      home: AppIconsScreen(service: service),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 250);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'icon selection follows native success and preserves selection on failure',
    (tester) async {
      final service = FakeIcons();
      await icons(tester, service);
      await tester.tap(find.text('Material 3'));
      await tester.pumpAndSettle();
      expect(service.name, 'material');
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Material 3'),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
      service.fail = true;
      await tester.tap(find.text('Midnight'));
      await tester.pumpAndSettle();
      expect(service.name, 'material');
      await reveal(tester, 'The icon could not be changed. Please try again.');
      expect(
        find.text('The icon could not be changed. Please try again.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('unsupported launcher leaves installed icon choices disabled', (
    tester,
  ) async {
    final service = FakeIcons()..canChange = false;
    await icons(tester, service);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Original'))
          .enabled,
      false,
    );
    await reveal(
      tester,
      'This device does not support changing the installed app icon.',
    );
    expect(
      find.text(
        'This device does not support changing the installed app icon.',
      ),
      findsOneWidget,
    );
  });
  test('theme and custom RGB survive a controller restart', () async {
    final store = MemoryPreferenceStore();
    final first = ScooterController(
      transport: FakeTransport(),
      preferences: store,
    );
    await first.setThemePreset(AppThemePreset.custom, color: 0x123456);
    first.dispose();
    final second = ScooterController(
      transport: FakeTransport(),
      preferences: store,
    );
    addTearDown(second.dispose);
    expect(second.themePreset, AppThemePreset.custom);
    expect(second.themeColor, 0xff123456);
    await second.setThemePreset(AppThemePreset.mint);
    expect(second.themeColor, AppThemePreset.mint.color);
    expect(second.customThemeColor, 0xff123456);
  });
  testWidgets('theme updates MaterialApp while preserving navigation', (
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
    final old = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await c.setThemePreset(AppThemePreset.mint);
    await tester.pumpAndSettle();
    final updated = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      updated.theme!.colorScheme.primary,
      isNot(old.theme!.colorScheme.primary),
    );
    expect(tester.state<NavigatorState>(find.byType(Navigator)), same(nav));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('speed settings show three sources and explain demo isolation', (
    tester,
  ) async {
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await c.startDemo();
    await tester.pumpWidget(
      MaterialApp(home: SpeedSourceScreen(controller: c)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.textContaining('Demo uses sample data'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('custom theme validates RGB before saving', (tester) async {
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: ThemeScreen(controller: c)));
    await tester.scrollUntilVisible(find.text('Custom'), 200);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'oops');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use color'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '00AA88');
    await tester.pump();
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();
    expect(c.themePreset, AppThemePreset.custom);
    expect(c.themeColor, 0xff00aa88);
  });
  testWidgets('personalization screens fit a narrow phone at large text', (
    tester,
  ) async {
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: MemoryPreferenceStore(),
    );
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in [
      ThemeScreen(controller: c),
      SpeedSourceScreen(controller: c),
      AppIconsScreen(service: FakeIcons()),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
