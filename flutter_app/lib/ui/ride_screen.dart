import 'package:flutter/material.dart';

import '../core/display_units.dart';
import '../core/telemetry.dart';
import '../services/scooter_controller.dart';
import '../services/phone_speed.dart';
import 'motion.dart';
import 'widgets.dart';
import 'theme.dart';

enum _DashboardSection { overview, totals, controls, modes, security }

class RideScreen extends StatefulWidget {
  const RideScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  _DashboardSection section = _DashboardSection.overview;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controller = widget.controller;
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
      final limited =
          constraints.maxHeight < 260 ||
          constraints.maxHeight < 420 && constraints.maxWidth < 650 ||
          constraints.maxHeight < 570 && largeText;
      if (limited) {
        final labels = <_DashboardSection, String>{
          _DashboardSection.overview: 'Overview',
          _DashboardSection.totals: 'Ride totals',
          _DashboardSection.controls: 'Controls',
          _DashboardSection.modes: 'Ride modes',
          _DashboardSection.security: 'Lock & find',
        };
        final content = switch (section) {
          _DashboardSection.overview => VehicleOverview(
            telemetry: controller.telemetry,
            speedEstimate: controller.displaySpeedEstimate,
            artwork: controller.artwork,
            compact: true,
          ),
          _DashboardSection.totals => Align(
            alignment: Alignment.topCenter,
            child: _TripSummary(controller.telemetry, compact: true),
          ),
          _DashboardSection.controls => _CompactControls(controller),
          _DashboardSection.modes => _RideModes(
            controller,
            vertical: constraints.maxWidth < 500,
          ),
          _DashboardSection.security => _LockActions(controller, stacked: true),
        };
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: 'Dashboard section',
                child: DropdownButton<_DashboardSection>(
                  value: section,
                  isExpanded: true,
                  isDense: false,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final entry in labels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => section = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StateTransition(
                child: KeyedSubtree(key: ValueKey(section), child: content),
              ),
            ),
          ],
        );
      }
      final compact = constraints.maxHeight < 550;
      final overview = Column(
        children: [
          Expanded(
            child: VehicleOverview(
              telemetry: controller.telemetry,
              speedEstimate: controller.displaySpeedEstimate,
              artwork: controller.artwork,
              compact: compact,
            ),
          ),
          const SizedBox(height: 12),
          _TripSummary(controller.telemetry, compact: compact),
        ],
      );
      final controls = _RideControls(controller, compact: compact);
      if (constraints.maxWidth >= 700) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 6, child: overview),
            const SizedBox(width: 20),
            Expanded(flex: 5, child: Center(child: controls)),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: overview),
          const SizedBox(height: 12),
          controls,
        ],
      );
    },
  );
}

class VehicleOverview extends StatelessWidget {
  const VehicleOverview({
    required this.telemetry,
    this.artwork = 'assets/scooter.png',
    this.compact = false,
    this.speedEstimate,
    super.key,
  });
  final Telemetry telemetry;
  final String artwork;
  final bool compact;
  final SpeedEstimate? speedEstimate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final surfaces = Theme.of(context).extension<RideSurfaces>();
      final battery = telemetry.integer(Reading.battery);
      final speed = speedEstimate == null
          ? telemetry[Reading.speed]
          : speedEstimate!.kmh;
      final numberSize = compact
          ? (constraints.maxHeight < 200 ? 20.0 : 26.0)
          : 32.0;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 12 : 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              surfaces?.heroStart ?? colors.surfaceContainerHigh,
              surfaces?.heroEnd ?? colors.surfaceContainerLow,
            ],
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Battery',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedMetricValue(
                        battery,
                        key: const ValueKey('dashboard-battery'),
                        unit: '%',
                        size: numberSize,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 64,
                        child: ExcludeSemantics(
                          child: LinearProgressIndicator(
                            value: battery == null
                                ? 0
                                : (battery / 100).clamp(0, 1),
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            backgroundColor: colors.outlineVariant,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Live speed',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        label: 'Speed',
                        value: speed == null
                            ? 'Not reported'
                            : '${DisplayUnits.distance(speed, telemetry.miles).round()} ${telemetry.miles ? 'miles per hour' : 'kilometers per hour'}',
                        child: ExcludeSemantics(
                          child: AnimatedMetricValue(
                            speed == null
                                ? null
                                : DisplayUnits.distance(speed, telemetry.miles),
                            key: const ValueKey('dashboard-speed'),
                            unit: telemetry.miles ? 'mph' : 'km/h',
                            size: numberSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (constraints.maxHeight > 190) ...[
              const SizedBox(height: 8),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: ScooterArt(artwork: artwork),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _TripSummary extends StatelessWidget {
  const _TripSummary(this.state, {this.compact = false});
  final Telemetry state;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    double? distance(Reading reading) => state[reading] == null
        ? null
        : DisplayUnits.distance(state[reading]!, state.miles);
    return Panel(
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (value, unit, label) in [
            (distance(Reading.trip), state.miles ? 'mi' : 'km', 'Trip'),
            (distance(Reading.odometer), state.miles ? 'mi' : 'km', 'Total'),
            (state[Reading.voltage], 'V', 'Voltage'),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedMetricValue(
                      value,
                      key: ValueKey('dashboard-${label.toLowerCase()}'),
                      unit: unit,
                      decimals: 1,
                      size: compact ? 18 : 21,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

List<(String, IconData, ScooterControl, Reading)> _visibleControls(
  ScooterController c,
) => [
  if (c.supports(Feature.headlight))
    (
      'Headlight',
      Icons.light_mode_outlined,
      ScooterControl.headlight,
      Reading.headlight,
    ),
  if (c.supports(Feature.cruise))
    ('Cruise', Icons.speed_rounded, ScooterControl.cruise, Reading.cruise),
  if (c.supports(Feature.kickStart))
    (
      'Kick start',
      Icons.electric_scooter_outlined,
      ScooterControl.kickStart,
      Reading.kickStart,
    ),
];

class _RideControls extends StatelessWidget {
  const _RideControls(this.controller, {this.compact = false});
  final ScooterController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final controls = _visibleControls(controller);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              if (controls.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final control in controls)
                      Expanded(
                        child: RideToggle(
                          label: control.$1,
                          icon: control.$2,
                          active: controller.telemetry.flag(control.$4),
                          busy: controller.pending(control.$3),
                          compact: compact,
                          onPressed:
                              !controller.canControl ||
                                  controller.telemetry.flag(control.$4) == null
                              ? null
                              : () => controller.toggle(
                                  control.$3,
                                  control.$4,
                                  control.$1,
                                ),
                        ),
                      ),
                  ],
                ),
              if (controls.isNotEmpty) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _RideModes(controller),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _LockActions(controller),
      ],
    );
  }
}

class _CompactControls extends StatelessWidget {
  const _CompactControls(this.controller);
  final ScooterController controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final items = <Widget>[
        for (final control in _visibleControls(controller))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: EdgeInsets.zero,
              child: Semantics(
                toggled: controller.telemetry.flag(control.$4),
                child: ListTile(
                  title: Text(control.$1, style: const TextStyle(fontSize: 14)),
                  trailing: Text(
                    controller.pending(control.$3)
                        ? '…'
                        : switch (controller.telemetry.flag(control.$4)) {
                            true => 'On',
                            false => 'Off',
                            null => '—',
                          },
                  ),
                  onTap:
                      controller.canControl &&
                          !controller.pending(control.$3) &&
                          controller.telemetry.flag(control.$4) != null
                      ? () => controller.toggle(
                          control.$3,
                          control.$4,
                          control.$1,
                        )
                      : null,
                ),
              ),
            ),
          ),
      ];
      return constraints.maxWidth > 500
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final item in items) Expanded(child: item)],
            )
          : Column(mainAxisSize: MainAxisSize.min, children: items);
    },
  );
}

class _RideModes extends StatelessWidget {
  const _RideModes(this.controller, {this.vertical = false});
  final ScooterController controller;
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final buttons = <Widget>[];
    for (final (gear, label, icon, light, night) in [
      (
        1,
        'Eco',
        Icons.eco_outlined,
        const Color(0xff16713f),
        const Color(0xff83d8a7),
      ),
      (
        2,
        'Drive',
        Icons.electric_scooter_outlined,
        const Color(0xff225ac7),
        const Color(0xffa4c3ff),
      ),
      (
        3,
        'Sport',
        Icons.bolt_outlined,
        const Color(0xffbc2835),
        const Color(0xffffa5ac),
      ),
    ]) {
      final selected = controller.telemetry.gear == gear;
      final tone = dark ? night : light;
      final enabled =
          controller.canControl &&
          controller.supportsControl(ScooterControl.gear) &&
          !controller.pending(ScooterControl.gear) &&
          (controller.telemetry.availableGears?.contains(gear) ?? true);
      buttons.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: Semantics(
            selected: selected,
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.feedback),
              curve: AppMotion.curve,
              decoration: BoxDecoration(
                color: selected
                    ? tone.withValues(alpha: dark ? .16 : .09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? tone : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: TextButton(
                key: ValueKey('gear-$gear'),
                onPressed: enabled ? () => controller.setGear(gear) : null,
                style: TextButton.styleFrom(
                  foregroundColor: tone,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(label, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: buttons,
          )
        : Row(
            children: [for (final button in buttons) Expanded(child: button)],
          );
  }
}

class _LockActions extends StatelessWidget {
  const _LockActions(this.controller, {this.stacked = false});
  final ScooterController controller;
  final bool stacked;
  @override
  Widget build(BuildContext context) {
    final state = controller.telemetry;
    final lock = FilledButton.icon(
      onPressed:
          !controller.supportsControl(ScooterControl.lock) ||
              state.locked == null ||
              controller.pending(ScooterControl.lock)
          ? null
          : controller.toggleLock,
      icon: controller.pending(ScooterControl.lock)
          ? const ConnectionProgress()
          : const Icon(Icons.lock_outline_rounded, size: 20),
      label: Text(state.locked == null ? 'Waiting for status' : 'Lock scooter'),
    );
    final find = OutlinedButton.icon(
      onPressed:
          !controller.supportsControl(ScooterControl.find) ||
              controller.pending(ScooterControl.find)
          ? null
          : controller.findScooter,
      icon: const Icon(Icons.volume_up_outlined, size: 20),
      label: const Text('Find'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
    if (stacked || MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [lock, const SizedBox(height: 12), find],
      );
    }
    return Row(
      children: [
        Expanded(child: lock),
        const SizedBox(width: 12),
        SizedBox(width: 100, child: find),
      ],
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    required this.controller,
    required this.onConnect,
    super.key,
  });
  final ScooterController controller;
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final short = constraints.maxHeight < 450;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!short) const Spacer(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.bluetooth_rounded,
                      size: 30,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  controller.reconnecting
                      ? 'Reconnecting…'
                      : controller.saved == null
                      ? 'Add your scooter'
                      : 'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  controller.reconnecting
                      ? 'Looking for ${controller.saved!.name}. Keep your scooter switched on and nearby.'
                      : controller.saved == null
                      ? 'A few quick steps to connect your scooter and see its live status.'
                      : 'Connect to ${controller.saved!.name} to view its status and controls.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
                if (!short)
                  const Spacer(flex: 2)
                else
                  const SizedBox(height: 24),
                FilledButton(
                  onPressed: controller.reconnecting
                      ? controller.disconnect
                      : onConnect,
                  child: Text(
                    controller.reconnecting
                        ? 'Cancel reconnect'
                        : controller.saved == null
                        ? 'Set up scooter'
                        : 'Connect my scooter',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: controller.startDemo,
                  child: const Text('Try Demo Mode'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}
