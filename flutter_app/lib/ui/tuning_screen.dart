import 'package:flutter/material.dart';

import '../core/display_units.dart';
import '../core/telemetry.dart';
import '../services/scooter_controller.dart';
import 'widgets.dart';
import 'dialogs.dart';

class TuningScreen extends StatefulWidget {
  const TuningScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  State<TuningScreen> createState() => _TuningScreenState();
}

class _TuningScreenState extends State<TuningScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.readSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.supportsControl(ScooterControl.maxSpeed) &&
            controller.range(ScooterControl.maxSpeed) != null)
          _SpeedSetting(controller: controller),
        if (![
          ScooterControl.maxSpeed,
          ScooterControl.startTorque,
          ScooterControl.maxTorque,
          ScooterControl.brake,
        ].any(controller.supportsControl))
          const Panel(
            child: Text(
              'Ride tuning is not available for this scooter integration.',
            ),
          ),
        if (controller.tuningNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              controller.tuningNotice!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        const SectionLabel('Acceleration & braking'),
        _ConfigSlider(
          controller: controller,
          title: 'Starting torque',
          subtitle: 'Acceleration when starting from a stop.',
          code: ScooterControl.startTorque,
          reading: Reading.startTorque,
          initial: 5,
          icon: Icons.moving_rounded,
        ),
        const SizedBox(height: 12),
        _ConfigSlider(
          controller: controller,
          title: 'Driving torque',
          subtitle: 'Motor response while riding.',
          code: ScooterControl.maxTorque,
          reading: Reading.maxTorque,
          initial: 5,
          icon: Icons.bolt_rounded,
        ),
        const SizedBox(height: 12),
        _ConfigSlider(
          controller: controller,
          title: 'Brake strength',
          subtitle: 'Electromagnetic braking response.',
          code: ScooterControl.brake,
          reading: Reading.brakeStrength,
          initial: 4,
          icon: Icons.pan_tool_alt_outlined,
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: controller.readingSettings || !controller.canControl
                ? null
                : () async {
                    final restore = await showAppDialog<bool>(
                      context: context,
                      builder: (context) => AppDialog(
                        title: const Text('Restore ride defaults?'),
                        icon: Icons.restart_alt_rounded,
                        content: const Text(
                          'The scooter will choose its own default speed, torque and brake settings.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                    );
                    if (restore == true) await controller.resetTuning();
                  },
            icon: const Icon(Icons.restart_alt_rounded, size: 19),
            label: const Text('Restore scooter defaults'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Settings remain at the last reported value until the scooter replies. Available limits depend on its model and firmware.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SpeedSetting extends StatefulWidget {
  const _SpeedSetting({required this.controller});
  final ScooterController controller;
  @override
  State<_SpeedSetting> createState() => _SpeedSettingState();
}

class _SpeedSettingState extends State<_SpeedSetting> {
  double draft = 25;
  int? lastReported;
  bool wasPending = false;
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final limit = controller.range(ScooterControl.maxSpeed)!;
    final actual = controller.telemetry.integer(Reading.maxSpeed);
    final pending = controller.pending(ScooterControl.maxSpeed);
    if (actual != lastReported || (wasPending && !pending)) {
      draft =
          (controller.range(ScooterControl.maxSpeed)?.clamp(actual ?? 25) ?? 25)
              .toDouble();
      lastReported = actual;
    }
    draft = limit.clamp(draft.round()).toDouble();
    wasPending = pending;
    final enabled =
        controller.canControl && !pending && !controller.readingSettings;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Speed limit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (pending)
                const SizedBox(
                  height: 17,
                  width: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 9,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                draft.round().toString(),
                style: const TextStyle(
                  fontSize: 40,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'km/h',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (controller.telemetry.miles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '≈ ${DisplayUnits.distance(draft, true).round()} mph',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Slider.adaptive(
            value: draft,
            min: limit.min.toDouble(),
            max: limit.max.toDouble(),
            divisions: limit.max - limit.min,
            label: '${draft.round()} km/h',
            onChanged: enabled
                ? (value) => setState(() => draft = value)
                : null,
          ),
          Wrap(
            spacing: 7,
            runSpacing: 4,
            children: [
              for (final speed in {
                limit.min,
                5,
                15,
                25,
                40,
                limit.max,
              }.where((v) => v >= limit.min && v <= limit.max).toList()..sort())
                ChoiceChip(
                  label: Text('$speed'),
                  selected: draft.round() == speed,
                  showCheckmark: false,
                  onSelected: enabled
                      ? (_) => setState(() => draft = speed.toDouble())
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled
                  ? () => controller.setConfig(
                      ScooterControl.maxSpeed,
                      draft.round(),
                    )
                  : null,
              child: Text(pending ? 'Waiting for scooter…' : 'Apply limit'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scooter reports: ${actual == null ? 'not reported' : '$actual km/h'}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Available speed limits depend on your scooter model and firmware.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigSlider extends StatefulWidget {
  const _ConfigSlider({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.code,
    required this.reading,
    required this.initial,
    required this.icon,
  });
  final ScooterController controller;
  final String title;
  final String subtitle;
  final ScooterControl code;
  final Reading reading;
  final int initial;
  final IconData icon;
  @override
  State<_ConfigSlider> createState() => _ConfigSliderState();
}

class _ConfigSliderState extends State<_ConfigSlider> {
  double? draft;
  int? lastReported;
  bool wasPending = false;
  @override
  Widget build(BuildContext context) {
    final range = widget.controller.range(widget.code);
    if (!widget.controller.supportsControl(widget.code) || range == null) {
      return const SizedBox.shrink();
    }
    final actual = widget.controller.telemetry.integer(widget.reading);
    final busy = widget.controller.pending(widget.code);
    if (draft == null || actual != lastReported || (wasPending && !busy)) {
      draft = (actual ?? widget.initial).clamp(range.min, range.max).toDouble();
      lastReported = actual;
    }
    draft = draft!.clamp(range.min, range.max).toDouble();
    wasPending = busy;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${draft!.round()} / ${range.max}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            widget.subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Slider.adaptive(
            value: draft!,
            min: range.min.toDouble(),
            max: range.max.toDouble(),
            divisions: range.max - range.min,
            label: '${draft!.round()}',
            onChanged:
                !widget.controller.canControl ||
                    busy ||
                    widget.controller.readingSettings
                ? null
                : (value) => setState(() => draft = value),
            onChangeEnd: (value) =>
                widget.controller.setConfig(widget.code, value.round()),
          ),
          Text(
            busy
                ? 'Waiting for confirmation…'
                : 'Scooter reports: ${actual?.toString() ?? 'not reported'}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
