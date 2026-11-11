import 'dart:math' as math;

import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  test('large themed surfaces retain readable text for presets and custom extremes', () {
    final seeds = [
      for (final p in AppThemePreset.values) Color(p.color),
      Colors.white,
      Colors.black,
      Colors.yellow,
      Colors.cyan,
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];
    for (final brightness in Brightness.values) {
      for (final seed in seeds) {
        final theme = rideTheme(brightness, seed: seed);
        final colors = theme.colorScheme;
        final surfaces = theme.extension<RideSurfaces>()!;
        for (final surface in [
          colors.surface,
          colors.surfaceContainerLow,
          colors.surfaceContainerHigh,
          colors.surfaceContainerHighest,
          surfaces.backdropStart,
          surfaces.backdropEnd,
          surfaces.heroStart,
          surfaces.heroEnd,
        ]) {
          for (final text in [
            colors.onSurface,
            colors.onSurfaceVariant,
            colors.primary,
          ]) {
            expect(
              contrast(text, surface),
              greaterThanOrEqualTo(4.5),
              reason: '$brightness seed $seed, text $text on $surface',
            );
          }
        }
        expect(
          contrast(colors.onPrimaryContainer, colors.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          theme.appBarTheme.systemOverlayStyle!.statusBarIconBrightness,
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        expect(
          contrast(colors.onSecondaryContainer, colors.secondaryContainer),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
  test('theme choice changes backgrounds, cards, dashboard and navigation', () {
    for (final brightness in Brightness.values) {
      final ocean = rideTheme(brightness);
      final mint = rideTheme(
        brightness,
        seed: Color(AppThemePreset.mint.color),
      );
      final a = ocean.extension<RideSurfaces>()!,
          b = mint.extension<RideSurfaces>()!;
      for (final pair in [
        (a.backdropStart, b.backdropStart),
        (a.heroStart, b.heroStart),
        (ocean.cardTheme.color!, mint.cardTheme.color!),
        (
          ocean.navigationBarTheme.backgroundColor!,
          mint.navigationBarTheme.backgroundColor!,
        ),
      ]) {
        final delta =
            (pair.$1.r - pair.$2.r).abs() +
            (pair.$1.g - pair.$2.g).abs() +
            (pair.$1.b - pair.$2.b).abs();
        expect(delta, greaterThan(.14));
      }
      expect(
        mint.navigationBarTheme.indicatorColor,
        mint.colorScheme.secondaryContainer,
      );
    }
  });
  test('theme transition interpolates the large background areas', () {
    final a = rideTheme(Brightness.dark).extension<RideSurfaces>()!;
    final b = rideTheme(
      Brightness.dark,
      seed: Color(AppThemePreset.sunset.color),
    ).extension<RideSurfaces>()!;
    final middle = a.lerp(b, .5);
    expect(
      middle.backdropStart,
      Color.lerp(a.backdropStart, b.backdropStart, .5),
    );
    expect(middle.heroStart, Color.lerp(a.heroStart, b.heroStart, .5));
  });
}
