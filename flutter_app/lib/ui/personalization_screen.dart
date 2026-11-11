import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_icons.dart';
import '../services/phone_speed.dart';
import '../services/preferences.dart';
import '../services/scooter_controller.dart';
import 'dialogs.dart';
import 'widgets.dart';

class SpeedSourceScreen extends StatelessWidget {
  const SpeedSourceScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final estimate = controller.displaySpeedEstimate;
      return Scaffold(
        appBar: AppBar(title: const Text('Speed calculation')),
        body: SafeArea(
          child: ListView(
            padding: pageInsets(context),
            children: [
              const Text(
                'Choose where live dashboard speed comes from. Scooter settings, trip and total distance continue to use scooter reports.',
              ),
              const SizedBox(height: 16),
              for (final source in SpeedSource.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(source.label),
                      subtitle: Text(switch (source) {
                        SpeedSource.scooter => 'Use the scooter’s wheel-speed report. No phone location needed.',
                        SpeedSource.phone => 'Use fresh phone GPS speed. Shows a dash while a reliable reading is unavailable.',
                        SpeedSource.mixed => 'Blend fresh readings that agree. Use reliable GPS on a large disagreement; fall back when a source drops out.',
                      }),
                      trailing: controller.speedSource == source
                          ? const Icon(Icons.check_circle_rounded)
                          : const Icon(Icons.circle_outlined),
                      enabled: !controller.selectingSpeedSource,
                      onTap: () => controller.setSpeedSource(source),
                    ),
                  ),
                ),
              if (controller.selectingSpeedSource)
                const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.isDemo ? 'Demo readings' : estimate.origin,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      controller.isDemo
                          ? 'Demo uses sample data. Phone speed starts with a real scooter connection.'
                          : controller.phoneSpeed.status ?? 'Mixed speed is an estimate, not a calibrated measurement.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Phone speed needs location access and works best outdoors with Precise Location enabled. It runs only while a scooter is connected and the app is in the foreground. Location coordinates are not stored or included in logs.',
                    ),
                    TextButton(
                      onPressed: openAppSettings,
                      child: const Text('Open phone settings'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: SafeArea(
        child: ListView(
          padding: pageInsets(context),
          children: [
            const Text(
              'Color the whole app: backgrounds, cards, dashboard and navigation. Light, Dark and System appearance remain available in Settings.',
            ),
            const SizedBox(height: 16),
            for (final preset in AppThemePreset.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(
                        preset == AppThemePreset.custom
                            ? controller.customThemeColor
                            : preset.color,
                      ),
                    ),
                    title: Text(preset.label),
                    trailing: controller.themePreset == preset
                        ? const Icon(Icons.check_circle_rounded)
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      if (preset != AppThemePreset.custom) {
                        await controller.setThemePreset(preset);
                        return;
                      }
                      final color = await _chooseColor(
                        context,
                        controller.customThemeColor,
                        'Custom theme',
                      );
                      if (color != null) {
                        await controller.setThemePreset(preset, color: color);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<int?> _chooseColor(BuildContext context, int initial, String title) =>
    showAppDialog<int>(
      context: context,
      builder: (_) => _ColorDialog(initial: initial, title: title),
    );

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial, required this.title});
  final int initial;
  final String title;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final input = TextEditingController(
    text: (widget.initial & 0xffffff)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase(),
  );
  int? get parsed => RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(input.text)
      ? 0xff000000 | int.parse(input.text, radix: 16)
      : null;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.title),
    icon: Icons.palette_outlined,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Color(parsed ?? widget.initial),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: input,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: 'Hex color',
            prefixText: '#',
            errorText: parsed == null
                ? 'Use six hex digits, for example 2563EB'
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: parsed == null ? null : () => Navigator.pop(context, parsed),
        child: const Text('Use color'),
      ),
    ],
  );
}

class AppIconArt extends StatelessWidget {
  const AppIconArt({
    required this.background,
    required this.foreground,
    this.size = 72,
    super.key,
  });
  final Color background, foreground;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: CustomPaint(
      size: Size.square(size),
      painter: _IconPainter(background, foreground),
    ),
  );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.background, this.foreground);
  final Color background, foreground;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.save();
    canvas.scale(size.width / 1024, size.height / 1024);
    canvas.drawOval(
      const Rect.fromLTRB(223, 223, 801, 801),
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 66,
    );
    final bolt = Path()
      ..moveTo(550, 270)
      ..lineTo(365, 560)
      ..lineTo(488, 560)
      ..lineTo(451, 755)
      ..lineTo(664, 448)
      ..lineTo(540, 448)
      ..close();
    canvas.drawPath(bolt, Paint()..color = foreground);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      background != old.background || foreground != old.foreground;
}

class AppIconsScreen extends StatefulWidget {
  const AppIconsScreen({this.service, super.key});
  final AppIconService? service;
  @override
  State<AppIconsScreen> createState() => _AppIconsScreenState();
}

class _AppIconsScreenState extends State<AppIconsScreen>
    with WidgetsBindingObserver {
  late final service = widget.service ?? AppIconService();
  Map<Object?, Object?> info = {};
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) _load();
  }

  Future<void> _load() async {
    try {
      final result = await service.capabilities();
      if (mounted) {
        setState(() {
          info = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Icon changes are unavailable on this device.');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'The icon could not be changed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App icon')),
      body: SafeArea(
        child: ListView(
          padding: pageInsets(context),
          children: [
            const Text(
              'Choose a bundled icon for the installed app. Your launcher may take a moment to refresh.',
            ),
            const SizedBox(height: 16),
            for (final preset in AppIconPreset.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: AppIconArt(
                      background: Color(preset.background),
                      foreground: Color(preset.foreground),
                      size: 48,
                    ),
                    title: Text(preset.label),
                    trailing: info['name'] == preset.name
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                    enabled: !busy && info['canChange'] == true,
                    onTap: () => _run(() => service.select(preset)),
                  ),
                ),
              ),
            if (info['canChange'] == false)
              const Text(
                'This device does not support changing the installed app icon.',
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
