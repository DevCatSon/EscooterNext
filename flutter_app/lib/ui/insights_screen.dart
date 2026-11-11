import 'package:flutter/material.dart';

import '../core/telemetry.dart';
import '../core/display_units.dart';
import '../services/scooter_controller.dart';
import 'widgets.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) {
    final state = controller.telemetry;
    Widget rows(List<(String, Reading, String)> list) => Column(
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 25),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(list[i].$1)),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  state[list[i].$2] == null
                      ? '—'
                      : '${state[list[i].$2]}${list[i].$3}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    Widget details(
      String title,
      IconData icon,
      Widget content, {
      bool expanded = false,
    }) => Panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey('sensor-details-$title'),
        initiallyExpanded: expanded,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon, size: 22),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [const SizedBox(height: 8), content],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: StatusNote(
            'Live readings from your scooter. Unavailable values appear as a dash.',
          ),
        ),
        ReadingGrid(
          children: [
            ReadingTile(
              label: 'Battery charge',
              value: state.integer(Reading.battery)?.toString() ?? '—',
              unit: '%',
              icon: Icons.battery_5_bar_outlined,
            ),
            ReadingTile(
              label: 'Voltage',
              value: state[Reading.voltage]?.toStringAsFixed(1) ?? '—',
              unit: 'V',
              icon: Icons.bolt_outlined,
            ),
          ],
        ),
        const SectionLabel('Temperature'),
        ReadingGrid(
          children: [
            ReadingTile(
              label: 'Controller',
              value: DisplayUnits.temperatureText(
                state[Reading.controllerTemp],
                controller.fahrenheit,
              ),
              unit: controller.fahrenheit ? '°F' : '°C',
              icon: Icons.memory_outlined,
            ),
            ReadingTile(
              label: 'Motor',
              value: DisplayUnits.temperatureText(
                state[Reading.motorTemp],
                controller.fahrenheit,
              ),
              unit: controller.fahrenheit ? '°F' : '°C',
              icon: Icons.settings_outlined,
            ),
            ReadingTile(
              label: 'Battery',
              value: DisplayUnits.temperatureText(
                state[Reading.batteryTemp],
                controller.fahrenheit,
              ),
              unit: controller.fahrenheit ? '°F' : '°C',
              icon: Icons.battery_charging_full_outlined,
            ),
          ],
        ),
        const SectionLabel('Details'),
        details(
          'Battery pack',
          Icons.battery_std_outlined,
          state[Reading.bmsId] == null
              ? const StatusNote(
                  'Battery-pack data has not been reported. Availability depends on your model.',
                )
              : Column(
                  children: [
                    rows([
                      ('Voltage', Reading.bmsVoltage, ' V'),
                      ('Current · unit unconfirmed', Reading.bmsCurrent, ''),
                      ('Charge cycles', Reading.bmsCycles, ''),
                      ('Rated capacity · raw', Reading.bmsRated, ''),
                      ('Remaining capacity · raw', Reading.bmsRemaining, ''),
                      ('Temperature · raw', Reading.bmsTemperature, ''),
                    ]),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final (bit, text) in [
                          (0, 'Charging'),
                          (1, 'Discharging'),
                          (2, 'Low voltage'),
                          (3, 'High voltage'),
                          (4, 'Battery anomaly'),
                        ])
                          if (((state.integer(Reading.bmsFlags) ?? 0) &
                                  (1 << bit)) !=
                              0)
                            Chip(label: Text(text)),
                      ],
                    ),
                    const StatusNote(
                      'Current, raw capacity and temperature units are unconfirmed.',
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        details(
          'Motor & brake signals',
          Icons.sensors_outlined,
          Column(
            children: [
              rows([
                ('Motor speed · raw', Reading.motorSpeed, ''),
                ('Current · raw', Reading.current, ''),
                ('Throttle', Reading.throttle, ''),
                ('Throttle · raw', Reading.throttleRaw, ''),
                ('Brake 1', Reading.brake1, ''),
                ('Brake 1 · raw', Reading.brake1Raw, ''),
                ('Brake 2', Reading.brake2, ''),
                ('Brake 2 · raw', Reading.brake2Raw, ''),
              ]),
              const SizedBox(height: 16),
              const StatusNote(
                'Raw sensor values are shown without assumed units.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        details(
          'Hardware & firmware',
          Icons.developer_board_outlined,
          Column(
            children: [
              rows([
                ('Dashboard hardware', Reading.instrumentHardware, ''),
                ('Dashboard software', Reading.instrumentSoftware, ''),
                ('Controller hardware', Reading.controllerHardware, ''),
                ('Controller software', Reading.controllerSoftware, ''),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: controller.queryVersions,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh versions'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
