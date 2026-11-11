import 'package:flutter/material.dart';

import 'motion.dart';

/// Brief, reversible popup motion; Reduce Motion presents the content directly.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    RawDialogRoute<T>(
      settings: const RouteSettings(name: 'app-dialog'),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0xff071322).withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .42 : .28,
      ),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      requestFocus: true,
      transitionDuration: AppMotion.duration(context, AppMotion.popup),
      pageBuilder: (context, animation, secondaryAnimation) =>
          themes.wrap(SafeArea(child: Builder(builder: builder))),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        if (AppMotion.reduced(context)) return child;
        final progress = animation.drive(
          CurveTween(curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: progress,
          child: SlideTransition(
            position: progress.drive(
              Tween(begin: const Offset(0, .025), end: Offset.zero),
            ),
            child: ScaleTransition(
              scale: progress.drive(Tween(begin: .96, end: 1.0)),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    this.icon = Icons.tune_rounded,
    this.accent,
    this.content,
    this.actions = const [],
    super.key,
  });
  final Widget title;
  final IconData icon;
  final Color? accent;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = accent ?? theme.colorScheme.primary;
    final surface = theme.colorScheme.surfaceContainerLow;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(tone.withValues(alpha: .12), surface),
                surface,
              ],
            ),
            border: Border.all(color: tone.withValues(alpha: .28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(largeText ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            tone.withValues(alpha: .24),
                            tone.withValues(alpha: .08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: tone, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DefaultTextStyle(
                        style: theme.textTheme.titleLarge!,
                        child: title,
                      ),
                    ),
                  ],
                ),
                if (content != null) ...[
                  const SizedBox(height: 24),
                  DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!,
                    child: content!,
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppDialogOption<T> {
  const AppDialogOption({
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });
  final T value;
  final String label;
  final IconData icon;
  final Color? color;
}

class AppChoiceDialog<T> extends StatefulWidget {
  const AppChoiceDialog({
    required this.title,
    required this.icon,
    required this.options,
    this.selected,
    this.accent,
    super.key,
  });
  final String title;
  final IconData icon;
  final List<AppDialogOption<T>> options;
  final T? selected;
  final Color? accent;
  @override
  State<AppChoiceDialog<T>> createState() => _AppChoiceDialogState<T>();
}

class _AppChoiceDialogState<T> extends State<AppChoiceDialog<T>> {
  late T? selected = widget.selected;
  bool closing = false;
  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.title),
    icon: widget.icon,
    accent: widget.accent,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _option(widget.options[i]),
        ],
      ],
    ),
  );

  Widget _option(AppDialogOption<T> option) {
    final colors = Theme.of(context).colorScheme;
    final tone = option.color ?? widget.accent ?? colors.primary;
    final active = selected == option.value;
    return Semantics(
      selected: active,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.feedback),
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: active
              ? tone.withValues(alpha: .14)
              : colors.surface.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? tone.withValues(alpha: .65) : colors.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: closing
                ? null
                : () {
                    setState(() {
                      selected = option.value;
                      closing = true;
                    });
                    Navigator.pop(context, option.value);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(option.icon, color: tone, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: Icon(
                      active
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: active ? tone : colors.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
