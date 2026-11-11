import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A full-width touch target with one accessible switch, including busy state.
class ControlSwitchRow extends StatelessWidget {
  const ControlSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.busy = false,
    super.key,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final change = busy || value == null ? null : onChanged;
    void toggle() => change?.call(!value!);
    return Semantics(
      label: label,
      toggled: value,
      value: busy
          ? 'Updating'
          : value == null
          ? 'Not reported'
          : null,
      enabled: change != null,
      onTap: change == null ? null : toggle,
      child: ExcludeSemantics(
        child: _ControlSurface(
          onTap: change == null ? null : toggle,
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 16),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (value == null)
                Flexible(
                  child: Text(
                    'Not reported',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                CupertinoSwitch(
                  value: value!,
                  onChanged: change,
                  activeTrackColor: const Color(0xff32d000),
                  thumbColor: Colors.white,
                  inactiveTrackColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xff454548)
                      : const Color(0xffbfc3c9),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ControlValueRow extends StatelessWidget {
  const ControlValueRow({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _ControlSurface(
    onTap: onTap,
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 18))),
        const SizedBox(width: 16),
        Flexible(
          fit: FlexFit.tight,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.chevron_right_rounded,
          size: 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    ),
  );
}

class _ControlSurface extends StatelessWidget {
  const _ControlSurface({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: child,
          ),
        ),
      ),
    ),
  );
}
