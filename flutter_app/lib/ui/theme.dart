import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'motion.dart';

abstract final class RideColors {
  static const blue = Color(0xff2563eb);
}

/// Shared large-area colors, interpolated by Flutter when the theme changes.
@immutable
class RideSurfaces extends ThemeExtension<RideSurfaces> {
  const RideSurfaces({
    required this.backdropStart,
    required this.backdropEnd,
    required this.heroStart,
    required this.heroEnd,
  });
  final Color backdropStart, backdropEnd, heroStart, heroEnd;
  @override
  RideSurfaces copyWith({
    Color? backdropStart,
    Color? backdropEnd,
    Color? heroStart,
    Color? heroEnd,
  }) => RideSurfaces(
    backdropStart: backdropStart ?? this.backdropStart,
    backdropEnd: backdropEnd ?? this.backdropEnd,
    heroStart: heroStart ?? this.heroStart,
    heroEnd: heroEnd ?? this.heroEnd,
  );
  @override
  RideSurfaces lerp(covariant RideSurfaces? other, double t) => other == null
      ? this
      : RideSurfaces(
          backdropStart: Color.lerp(backdropStart, other.backdropStart, t)!,
          backdropEnd: Color.lerp(backdropEnd, other.backdropEnd, t)!,
          heroStart: Color.lerp(heroStart, other.heroStart, t)!,
          heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
        );
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = theme.extension<RideSurfaces>();
    return DecoratedBox(
      key: const ValueKey('app-gradient'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surfaces?.backdropStart ?? theme.colorScheme.surface,
            theme.colorScheme.surface,
            surfaces?.backdropEnd ?? theme.colorScheme.surface,
          ],
          stops: const [0, .6, 1],
        ),
      ),
      child: child,
    );
  }
}

ThemeData rideTheme(
  Brightness brightness, {
  TargetPlatform? platform,
  Color seed = RideColors.blue,
  bool monochrome = false,
}) {
  final dark = brightness == Brightness.dark;
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    contrastLevel: .5,
    dynamicSchemeVariant: monochrome
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
    brightness: brightness,
  );
  final tint = monochrome ? const Color(0xff888888) : seed;
  Color tinted(Color base, double amount) =>
      Color.alphaBlend(tint.withValues(alpha: amount), base);
  final background = dark ? const Color(0xff101318) : const Color(0xfffbfcff);
  final panel = dark ? const Color(0xff20252d) : Colors.white;
  final colors = generated.copyWith(
    surface: tinted(background, dark ? .12 : .06),
    surfaceContainerLowest: tinted(background, dark ? .07 : .03),
    surfaceContainerLow: tinted(panel, dark ? .18 : .20),
    surfaceContainer: tinted(panel, dark ? .20 : .22),
    surfaceContainerHigh: tinted(panel, dark ? .23 : .24),
    surfaceContainerHighest: tinted(panel, dark ? .25 : .26),
    onSurface: dark ? const Color(0xfff5f6fa) : const Color(0xff171c25),
    onSurfaceVariant: dark ? const Color(0xffd8dce5) : const Color(0xff3b4554),
    outlineVariant: Color.alphaBlend(
      generated.primary.withValues(alpha: .24),
      panel,
    ),
  );
  final surfaces = RideSurfaces(
    backdropStart: tinted(background, dark ? .28 : .22),
    backdropEnd: tinted(background, dark ? .18 : .12),
    heroStart: tinted(panel, dark ? .26 : .25),
    heroEnd: tinted(panel, dark ? .14 : .12),
  );
  final base = ThemeData(
    useMaterial3: true,
    platform: platform,
    colorScheme: colors,
  );
  return base.copyWith(
    extensions: [surfaces],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: AccessiblePageTransitions(
          CupertinoPageTransitionsBuilder(),
        ),
        TargetPlatform.android: AccessiblePageTransitions(
          FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
        ),
      },
    ),
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.textTheme.copyWith(
      bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: colors.onSurface),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: colors.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: colors.onSurfaceVariant,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: colors.surfaceContainerHigh,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
      backgroundColor: Colors.transparent,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: colors.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: colors.onSurfaceVariant,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: colors.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: colors.outlineVariant),
      selectedColor: colors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(fontSize: 14, color: colors.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
    ),
  );
}
