import 'package:flutter/material.dart';

import 'motion.dart';

/// Context for a screen whose title is already in its app bar.
class PageHeading extends StatelessWidget {
  const PageHeading(this.eyebrow, this.title, {this.trailing, super.key});
  final String eyebrow;
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

class ReadingTile extends StatelessWidget {
  const ReadingTile({
    required this.label,
    required this.value,
    required this.icon,
    this.unit,
    super.key,
  });
  final String label;
  final String value;
  final IconData icon;
  final String? unit;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MetricValue(value, unit: unit, size: 24),
      ],
    ),
  );
}

class MetricValue extends StatelessWidget {
  const MetricValue(
    this.value, {
    this.unit,
    this.size = 26,
    this.color,
    this.textAlign = TextAlign.start,
    super.key,
  });
  final String value;
  final String? unit;
  final double size;
  final Color? color;
  final TextAlign textAlign;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: TextStyle(
            height: 1.15,
            fontSize: size,
            fontWeight: FontWeight.w600,
            letterSpacing: -.7,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color,
          ),
        ),
        if (unit != null)
          TextSpan(
            text: ' $unit',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
    textAlign: textAlign,
    maxLines: 2,
  );
}

/// Animate reported numbers without changing their stored values or semantics.
class AnimatedMetricValue extends StatelessWidget {
  const AnimatedMetricValue(
    this.value, {
    required this.unit,
    this.decimals = 0,
    this.size = 26,
    this.textAlign = TextAlign.start,
    super.key,
  });
  final num? value;
  final String unit;
  final int decimals;
  final double size;
  final TextAlign textAlign;
  String _format(num number) => decimals == 0
      ? number.round().toString()
      : number.toStringAsFixed(decimals);
  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return MetricValue('—', unit: unit, size: size, textAlign: textAlign);
    }
    return Semantics(
      value: '${_format(value!)} $unit',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          // A unit change should show the converted value immediately.
          key: ValueKey(unit),
          tween: Tween(begin: value!.toDouble(), end: value!.toDouble()),
          duration: AppMotion.duration(context, AppMotion.feedback),
          curve: AppMotion.curve,
          builder: (context, number, _) => MetricValue(
            _format(number),
            unit: unit,
            size: size,
            textAlign: textAlign,
          ),
        ),
      ),
    );
  }
}

class ReadingGrid extends StatelessWidget {
  const ReadingGrid({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 680 ? 3 : 2;
      final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class RideToggle extends StatelessWidget {
  const RideToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.busy,
    required this.onPressed,
    this.compact = false,
    super.key,
  });
  final String label;
  final IconData icon;
  final bool? active;
  final bool busy;
  final VoidCallback? onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = busy
        ? 'Updating'
        : active == null
        ? 'Unavailable'
        : active!
        ? 'On'
        : 'Off';
    return Semantics(
      button: true,
      toggled: active,
      enabled: !busy && onPressed != null,
      onTap: busy ? null : onPressed,
      label: label,
      value: busy ? 'Waiting for scooter confirmation' : status,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compact ? 8 : 12,
              horizontal: 4,
            ),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: AppMotion.duration(context, AppMotion.feedback),
                  curve: AppMotion.curve,
                  width: compact ? 36 : 44,
                  height: compact ? 36 : 44,
                  decoration: BoxDecoration(
                    color: active == true
                        ? colors.primaryContainer
                        : colors.surface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: active == true
                                ? colors.onPrimaryContainer
                                : colors.primary,
                          ),
                        )
                      : Icon(
                          icon,
                          size: 22,
                          color: active == true
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: active == true
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScooterArt extends StatelessWidget {
  const ScooterArt({
    this.height = 220,
    this.artwork = 'assets/scooter.png',
    super.key,
  });
  final double height;
  final String artwork;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: artwork == 'icon:scooter'
        ? Icon(
            Icons.electric_scooter_rounded,
            size: height.clamp(32, 150),
            color: Theme.of(context).colorScheme.primary,
          )
        : Image.asset(
            artwork,
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, error, stack) => Icon(
              Icons.electric_scooter_rounded,
              size: height.clamp(32, 150),
            ),
          ),
  );
}

class StatusNote extends StatelessWidget {
  const StatusNote(
    this.text, {
    this.icon = Icons.info_outline_rounded,
    super.key,
  });
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

EdgeInsets pageInsets(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return EdgeInsets.symmetric(
    horizontal: width > 712 ? (width - 680) / 2 : 16,
    vertical: 16,
  );
}
