import 'dart:async';

import 'package:flutter/material.dart';

import 'services/preferences.dart';
import 'services/scooter_controller.dart';
import 'ui/connect_screen.dart';
import 'ui/insights_screen.dart';
import 'ui/ride_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/tuning_screen.dart';
import 'ui/locked_panel.dart';
import 'ui/motion.dart';

class ScooterApp extends StatefulWidget {
  const ScooterApp({
    required this.controller,
    this.disposeController = false,
    this.platform,
    super.key,
  });
  final ScooterController controller;
  final bool disposeController;
  final TargetPlatform? platform;
  @override
  State<ScooterApp> createState() => _ScooterAppState();
}

class _ScooterAppState extends State<ScooterApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  bool _connectionScreenOpen = false;
  late bool _wasReady;
  late AppAppearance _appearance;
  late int _themeRevision;
  int _lastMessage = 0;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _wasReady = widget.controller.ready;
    _appearance = widget.controller.appearance;
    _themeRevision = widget.controller.themeRevision;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = widget.controller;
      if ((!c.hasSeenSetup && !c.ready) || (c.setupNamePending && !c.isDemo)) {
        unawaited(_openConnection());
      }
      c.startConnectionLifecycle();
    });
  }

  Future<void> _openConnection() async {
    if (_connectionScreenOpen || !mounted) return;
    _connectionScreenOpen = true;
    try {
      final opened = await _navigator.currentState!.push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ConnectScreen(controller: widget.controller),
        ),
      );
      if (mounted && (opened == true || !widget.controller.ready)) {
        setState(() => _tab = 0);
      }
    } finally {
      _connectionScreenOpen = false;
    }
  }

  @override
  void didUpdateWidget(ScooterApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onMessage);
    _wasReady = widget.controller.ready;
    _appearance = widget.controller.appearance;
    _themeRevision = widget.controller.themeRevision;
    _lastMessage = widget.controller.messageRevision;
    _tab = 0;
    widget.controller.addListener(_onMessage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.setAppActive(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.controller.setAppActive(false);
    }
  }

  void _onMessage() {
    final controller = widget.controller;
    if (_appearance != controller.appearance ||
        _themeRevision != controller.themeRevision) {
      setState(() {
        _appearance = controller.appearance;
        _themeRevision = controller.themeRevision;
      });
    }
    if (_wasReady != controller.ready) {
      final disconnected = _wasReady && !controller.ready;
      _wasReady = controller.ready;
      _tab = 0;
      if (disconnected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_connectionScreenOpen) {
            _navigator.currentState?.popUntil((route) => route.isFirst);
          }
        });
      }
    }
    if (_lastMessage == controller.messageRevision ||
        controller.message == null) {
      return;
    }
    _lastMessage = controller.messageRevision;
    final text = controller.message!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _messenger.currentState?.hideCurrentSnackBar();
        _messenger.currentState?.showSnackBar(
          SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onMessage);
    WidgetsBinding.instance.removeObserver(this);
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return MaterialApp(
      title: 'Escooter Next',
      debugShowCheckedModeBanner: false,
      themeAnimationDuration:
          WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations
          ? Duration.zero
          : AppMotion.feedback,
      scaffoldMessengerKey: _messenger,
      navigatorKey: _navigator,
      theme: rideTheme(
        Brightness.light,
        platform: widget.platform,
        seed: Color(controller.themeColor),
        monochrome: controller.themePreset == AppThemePreset.graphite,
      ),
      darkTheme: rideTheme(
        Brightness.dark,
        platform: widget.platform,
        seed: Color(controller.themeColor),
        monochrome: controller.themePreset == AppThemePreset.graphite,
      ),
      themeMode: switch (_appearance) {
        AppAppearance.system => ThemeMode.system,
        AppAppearance.light => ThemeMode.light,
        AppAppearance.dark => ThemeMode.dark,
      },
      builder: (context, child) => ListenableBuilder(
        listenable: controller,
        child: child,
        builder: (context, child) {
          final locked =
              controller.ready && controller.telemetry.locked == true;
          return AppBackdrop(
            child: Stack(
              children: [
                ExcludeSemantics(
                  excluding: locked,
                  child: child ?? const SizedBox.shrink(),
                ),
                Positioned.fill(
                  child: ScooterLockOverlay(controller: controller),
                ),
              ],
            ),
          );
        },
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          Future<void> connect() => _openConnection();

          final Widget page;
          if (_tab == 3) {
            page = SettingsScreen(controller: controller);
          } else if (!controller.ready) {
            page = WelcomeScreen(controller: controller, onConnect: connect);
          } else {
            page = switch (_tab) {
              1 => TuningScreen(controller: controller),
              2 => InsightsScreen(controller: controller),
              _ => RideScreen(controller: controller),
            };
          }
          final home = _tab == 0 || !controller.ready && _tab != 3;
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 28
                  ? 96
                  : 64,
              leading: !controller.ready && _tab == 3
                  ? IconButton(
                      onPressed: () => setState(() => _tab = 0),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back to scooter',
                    )
                  : null,
              title: home && controller.ready
                  ? InkWell(
                      onTap: connect,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    controller.scooterName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    controller.isDemo
                                        ? 'Demo vehicle'
                                        : controller.modelLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Text(
                      home
                          ? 'My scooter'
                          : const [
                              'My scooter',
                              'Ride settings',
                              'Sensors',
                              'Settings',
                            ][_tab],
                    ),
              actions: [
                if (controller.ready && _tab == 1)
                  IconButton(
                    onPressed: controller.readingSettings
                        ? null
                        : controller.readSettings,
                    tooltip: 'Refresh ride settings',
                    icon: controller.readingSettings
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                if (controller.ready)
                  IconButton(
                    onPressed: connect,
                    tooltip: 'Connection details',
                    icon: Icon(
                      controller.isDemo
                          ? Icons.science_outlined
                          : Icons.bluetooth_connected_rounded,
                      size: 22,
                    ),
                  ),
                if (!controller.ready && _tab != 3)
                  IconButton(
                    onPressed: () => setState(() => _tab = 3),
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'App settings',
                  ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _tab == 0
                        ? 1000
                        : _tab == 2
                        ? 900
                        : 680,
                  ),
                  child: _tab != 3 && (!controller.ready || _tab == 0)
                      ? Padding(
                          key: const ValueKey('fixed-dashboard'),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: page,
                        )
                      : ListView(
                          key: PageStorageKey('$_tab-${controller.ready}'),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [page],
                        ),
                ),
              ),
            ),
            bottomNavigationBar: controller.ready
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: (value) =>
                          setState(() => _tab = value),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.electric_scooter_outlined),
                          selectedIcon: Icon(Icons.electric_scooter_rounded),
                          label: 'Scooter',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.tune_outlined),
                          selectedIcon: Icon(Icons.tune_rounded),
                          label: 'Tuning',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.bar_chart_outlined),
                          selectedIcon: Icon(Icons.bar_chart_rounded),
                          label: 'Sensors',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings_rounded),
                          label: 'Settings',
                        ),
                      ],
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}
