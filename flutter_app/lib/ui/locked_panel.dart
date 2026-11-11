import 'package:flutter/material.dart';

import '../services/scooter_controller.dart';
import 'motion.dart';
import 'widgets.dart';

/// Animate reported lock changes without delaying or predicting the scooter state.
class ScooterLockOverlay extends StatefulWidget {
  const ScooterLockOverlay({required this.controller, super.key});
  final ScooterController controller;

  @override
  State<ScooterLockOverlay> createState() => _ScooterLockOverlayState();
}

class _ScooterLockOverlayState extends State<ScooterLockOverlay>
    with SingleTickerProviderStateMixin {
  late final _visibility = AnimationController(
    vsync: this,
    duration: AppMotion.transition,
  )..addStatusListener(_onStatus);
  late final _progress = _visibility.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  late final _position = _progress.drive(
    Tween(begin: const Offset(0, .025), end: Offset.zero),
  );
  bool _locked = false;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ScooterLockOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final locked =
        widget.controller.ready && widget.controller.telemetry.locked == true;
    final changed = locked != _locked;
    _locked = locked;
    if (!widget.controller.ready || AppMotion.reduced(context)) {
      _shown = locked;
      _visibility.value = locked ? 1 : 0;
    } else if (changed) {
      if (locked) {
        _shown = true;
        _visibility.forward();
      } else {
        _visibility.reverse();
      }
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_locked && _shown) {
      setState(() => _shown = false);
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    // The fading unlock snapshot has no actions or screen-reader focus.
    return IgnorePointer(
      ignoring: !_locked,
      child: ExcludeSemantics(
        excluding: !_locked,
        child: BlockSemantics(
          blocking: _locked,
          child: FadeTransition(
            key: const ValueKey('scooter-lock-fade'),
            opacity: _progress,
            alwaysIncludeSemantics: true,
            child: LockedPanel(
              controller: widget.controller,
              unlocked: !_locked,
              position: _position,
            ),
          ),
        ),
      ),
    );
  }
}

class LockedPanel extends StatelessWidget {
  const LockedPanel({
    required this.controller,
    required this.unlocked,
    required this.position,
    super.key,
  });
  final ScooterController controller;
  final bool unlocked;
  final Animation<Offset> position;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .97),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SlideTransition(
            position: position,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Panel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.duration(context, AppMotion.feedback),
                      child: Icon(
                        unlocked
                            ? Icons.lock_open_rounded
                            : Icons.lock_outline_rounded,
                        key: ValueKey(unlocked),
                        size: 36,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      unlocked ? 'Scooter unlocked' : 'Scooter locked',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      unlocked
                          ? 'Your controls are ready.'
                          : 'Unlock your scooter to access its controls.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            unlocked || controller.pending(ScooterControl.lock)
                            ? null
                            : controller.toggleLock,
                        icon: const Icon(Icons.lock_open_rounded, size: 18),
                        label: Text(
                          unlocked
                              ? 'Unlocked'
                              : controller.pending(ScooterControl.lock)
                              ? 'Waiting for scooter…'
                              : 'Unlock scooter',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: unlocked ? null : controller.disconnect,
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
