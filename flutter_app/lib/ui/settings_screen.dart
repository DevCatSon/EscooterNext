import 'package:flutter/material.dart';

import '../core/telemetry.dart';
import '../services/preferences.dart';
import '../services/scooter_controller.dart';
import 'diagnostics_screen.dart';
import 'control_rows.dart';
import 'scooter_models_screen.dart';
import 'widgets.dart';
import 'dialogs.dart';
import 'personalization_screen.dart';
import '../services/phone_speed.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));
    Widget group(List<Widget> rows) => Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: rows[i],
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.ready) ...[
          const SectionLabel('Vehicle'),
          group([
            ListTile(
              leading: const Icon(Icons.electric_scooter_outlined),
              title: const Text('Scooter name'),
              subtitle: Text(controller.scooterName),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _rename(context),
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth_rounded),
              title: Text(
                controller.isDemo ? 'Exit Demo Mode' : 'Disconnect scooter',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: controller.disconnect,
            ),
          ]),
        ],
        const SectionLabel('Controls'),
        group([
          ListTile(
            leading: const Icon(Icons.two_wheeler_outlined),
            title: const Text('Scooter models'),
            subtitle: Text(controller.modelLabel),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(ScooterModelsScreen(controller: controller)),
          ),
          ListTile(
            leading: const Icon(Icons.toggle_on_outlined),
            title: const Text('Feature support'),
            subtitle: const Text('Show controls available on your scooter'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(FeatureScreen(controller: controller)),
          ),
          if (controller.ready && controller.supports(Feature.ambient))
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Ambient lighting'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => open(AmbientScreen(controller: controller)),
            ),
          if (controller.ready &&
              [
                Feature.seat,
                Feature.helmet,
                Feature.storage,
                Feature.brakeLock,
              ].any(controller.supports))
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Compartments'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => open(CompartmentsScreen(controller: controller)),
            ),
        ]),
        const SectionLabel('Units'),
        ControlValueRow(
          label: 'Speed calculation',
          value: controller.speedSource.label,
          onTap: () => open(SpeedSourceScreen(controller: controller)),
        ),
        ControlValueRow(
          label: 'Speed & distance',
          value: controller.pending(ScooterControl.unit)
              ? 'Updating…'
              : !controller.ready
              ? 'Connect to scooter'
              : controller.telemetry.flag(Reading.miles) == null
              ? 'Not reported'
              : controller.telemetry.miles
              ? 'mph · mi'
              : 'km/h · km',
          onTap:
              controller.canControl &&
                  controller.telemetry.flag(Reading.miles) != null &&
                  controller.supportsControl(ScooterControl.unit) &&
                  !controller.pending(ScooterControl.unit)
              ? () => _chooseSpeedUnits(context)
              : null,
        ),
        ControlValueRow(
          label: 'Temperature',
          value: controller.fahrenheit ? 'Fahrenheit · °F' : 'Celsius · °C',
          onTap: () => _chooseTemperature(context),
        ),
        const SectionLabel('Connection'),
        ControlSwitchRow(
          label: 'Auto reconnect',
          value: controller.autoReconnect,
          onChanged: controller.setAutoReconnect,
        ),
        const SectionLabel('App'),
        group([
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(controller.themePreset.label),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(ThemeScreen(controller: controller)),
          ),
          ListTile(
            leading: const Icon(Icons.app_registration_rounded),
            title: const Text('App icon'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const AppIconsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.contrast_rounded),
            title: const Text('Appearance'),
            trailing: DropdownButton<AppAppearance>(
              value: controller.appearance,
              underline: const SizedBox.shrink(),
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              items: [
                for (final (value, label) in [
                  (AppAppearance.system, 'System'),
                  (AppAppearance.light, 'Light'),
                  (AppAppearance.dark, 'Dark'),
                ])
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (value) {
                if (value != null) controller.setAppearance(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.terminal_rounded),
            title: const Text('Diagnostics'),
            subtitle: const Text('Advanced connection tools'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(DiagnosticsScreen(controller: controller)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About Escooter Next'),
            subtitle: const Text('Version 1.0.0 · DevCatSon'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(const _AboutScreen()),
          ),
        ]),
        if (controller.saved != null) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final forget = await showAppDialog<bool>(
                  context: context,
                  builder: (context) => AppDialog(
                    title: const Text('Forget this scooter?'),
                    icon: Icons.link_off_rounded,
                    accent: Theme.of(context).colorScheme.error,
                    content: const Text(
                      'Disconnects and removes the saved connection on this phone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onError,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Forget'),
                      ),
                    ],
                  ),
                );
                if (forget == true) await controller.forget();
              },
              icon: const Icon(Icons.link_off_rounded, size: 20),
              label: const Text('Forget saved scooter'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: controller.scooterName),
    );
    if (name != null) await controller.rename(name);
  }

  Future<void> _chooseSpeedUnits(BuildContext context) async {
    final choice = await _chooseUnit(
      context,
      'Speed & distance',
      controller.telemetry.flag(Reading.miles),
      const [(false, 'Kilometres · km/h'), (true, 'Miles · mph')],
    );
    if (choice != null &&
        controller.canControl &&
        choice != controller.telemetry.flag(Reading.miles)) {
      await controller.setMiles(choice);
    }
  }

  Future<void> _chooseTemperature(BuildContext context) async {
    final choice = await _chooseUnit(
      context,
      'Temperature',
      controller.fahrenheit,
      const [(false, 'Celsius · °C'), (true, 'Fahrenheit · °F')],
      temperature: true,
    );
    if (choice != null) await controller.setFahrenheit(choice);
  }

  Future<bool?> _chooseUnit(
    BuildContext context,
    String title,
    bool? selected,
    List<(bool, String)> choices, {
    bool temperature = false,
  }) {
    return showAppDialog<bool>(
      context: context,
      builder: (context) => AppChoiceDialog<bool>(
        title: title,
        selected: selected,
        icon: temperature ? Icons.thermostat_rounded : Icons.speed_rounded,
        options: [
          for (final (value, label) in choices)
            AppDialogOption(
              value: value,
              label: label,
              icon: temperature
                  ? value
                        ? Icons.wb_sunny_outlined
                        : Icons.ac_unit_rounded
                  : Icons.route_outlined,
            ),
        ],
      ),
    );
  }
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escooter Next',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Flutter preview · 1.0.0'),
              const SizedBox(height: 24),
              Text('Privacy', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Preferences stay on this phone. No account, advertising or analytics. Bluetooth connects directly to your scooter. Optional Phone or Mixed speed uses foreground location while a scooter is connected; coordinates are not stored or included in logs.',
              ),
              const SizedBox(height: 24),
              const Text('© 2026 DevCatSon · MIT'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Escooter Next',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© 2026 DevCatSon',
                ),
                child: const Text('Open-source licenses'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});
  final String initialName;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final input = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('Name your scooter'),
    icon: Icons.edit_outlined,
    content: Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          controller: input,
          maxLength: 32,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Scooter name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class FeatureScreen extends StatelessWidget {
  const FeatureScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Feature support')),
      body: SafeArea(
        child: ListView(
          padding: pageInsets(context),
          children: [
            const PageHeading(
              'Visible controls',
              'Choose the features available on your model.',
            ),
            Text(
              'These switches show or hide controls. They do not unlock features restricted by the controller.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: controller.resetFeatures,
              child: const Text('Use model defaults'),
            ),
            const SizedBox(height: 16),
            for (final (feature, label) in [
              (Feature.headlight, 'Headlight'),
              (Feature.cruise, 'Cruise control'),
              (Feature.kickStart, 'Kick start'),
              (Feature.ambient, 'Ambient lighting'),
              (Feature.seat, 'Seat / cabin lock'),
              (Feature.helmet, 'Helmet box lock'),
              (Feature.storage, 'Storage basket lock'),
              (Feature.brakeLock, 'Brake lock'),
            ])
              ControlSwitchRow(
                label: label,
                value: controller.supports(feature),
                onChanged:
                    (controller.isDemo ||
                            controller.connectedId != null ||
                            controller.saved != null) &&
                        controller.supportsControl(feature.control)
                    ? (value) => controller.setFeature(feature, value)
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}

class AmbientScreen extends StatefulWidget {
  const AmbientScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  State<AmbientScreen> createState() => _AmbientScreenState();
}

class _AmbientScreenState extends State<AmbientScreen> {
  int? selectedMode;
  int hue = 32;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Ambient lighting')),
      body: SafeArea(
        child: ListView(
          padding: pageInsets(context),
          children: [
            const PageHeading(
              'Lighting mode',
              'Choose an effect and apply it to your scooter.',
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scooter reports: ${switch (widget.controller.telemetry.flag(Reading.ambient)) {
                      true => 'on',
                      false => 'off',
                      null => 'not reported',
                    }}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, label) in [
                        (1, 'Off'),
                        (2, 'Chase'),
                        (3, 'Banner'),
                        (4, 'Steady'),
                        (5, 'Color'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: selectedMode == value,
                          onSelected:
                              widget.controller.canControl &&
                                  !widget.controller.pending(
                                    ScooterControl.ambient,
                                  )
                              ? (_) => setState(() => selectedMode = value)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (selectedMode == 5)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (name, value, color) in [
                          ('Orange', 32, const Color(0xffff8901)),
                          ('Yellow', 51, const Color(0xfffad817)),
                          ('Green', 156, const Color(0xff00ba71)),
                          ('Blue', 187, const Color(0xff00c2de)),
                          ('White', 0, const Color(0xffeeeeee)),
                        ])
                          ChoiceChip(
                            label: Text(name),
                            avatar: CircleAvatar(backgroundColor: color),
                            selected: hue == value,
                            onSelected: (_) => setState(() => hue = value),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          selectedMode == null ||
                              !widget.controller.canControl ||
                              widget.controller.pending(ScooterControl.ambient)
                          ? null
                          : () => widget.controller.setAmbient(
                              selectedMode!,
                              hue,
                            ),
                      child: const Text('Apply lighting'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The scooter reports on/off state only. The selected mode and color are your choices, not a confirmed read-back.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CompartmentsScreen extends StatelessWidget {
  const CompartmentsScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Compartments')),
      body: SafeArea(
        child: ListView(
          padding: pageInsets(context),
          children: [
            const PageHeading(
              'Compartment controls',
              'Activate a compartment supported by your scooter.',
            ),
            for (final (feature, code, label, icon) in [
              (
                Feature.seat,
                ScooterControl.seat,
                'Seat / cabin',
                Icons.event_seat_outlined,
              ),
              (
                Feature.helmet,
                ScooterControl.helmet,
                'Helmet box',
                Icons.sports_motorsports_outlined,
              ),
              (
                Feature.storage,
                ScooterControl.storage,
                'Storage basket',
                Icons.shopping_basket_outlined,
              ),
              (
                Feature.brakeLock,
                ScooterControl.brakeLock,
                'Brake lock',
                Icons.lock_outline_rounded,
              ),
            ])
              if (controller.supports(feature))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text(label)),
                        OutlinedButton(
                          onPressed:
                              controller.canControl && !controller.pending(code)
                              ? () => controller.pulse(code)
                              : null,
                          child: const Text('Activate'),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 14),
            Text(
              'These are momentary controls. The protocol does not confirm a compartment’s persistent lock state; check it on the scooter.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
