import 'package:flutter/material.dart';

/// HIG-informed motion. Durations are app choices, not Apple requirements.
abstract final class AppMotion {
  static const feedback = Duration(milliseconds: 200);
  static const transition = Duration(milliseconds: 300);
  static const popup = Duration(milliseconds: 240);
  static const curve = Curves.easeInOutCubic;
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
  static Duration duration(BuildContext context, Duration normal) =>
      reduced(context) ? Duration.zero : normal;
}

/// Brief state transitions; Reduce Motion removes movement and animation.
class StateTransition extends StatelessWidget {
  const StateTransition({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: AppMotion.transition,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previous.map(
            (child) => IgnorePointer(child: ExcludeSemantics(child: child)),
          ),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}

/// Retain platform navigation gestures/transitions; suppress them for Reduce Motion.
class AccessiblePageTransitions extends PageTransitionsBuilder {
  const AccessiblePageTransitions(this.platformBuilder);
  final PageTransitionsBuilder platformBuilder;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    return platformBuilder.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

class ConnectionProgress extends StatelessWidget {
  const ConnectionProgress({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: AppMotion.reduced(context)
        ? Icon(
            Icons.bluetooth_searching_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          )
        : const CircularProgressIndicator(strokeWidth: 2),
  );
}
