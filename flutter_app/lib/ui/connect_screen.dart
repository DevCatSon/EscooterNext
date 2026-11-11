import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/preferences.dart';
import '../ble/ble_models.dart';
import '../services/scooter_controller.dart';
import 'motion.dart';
import 'widgets.dart';
import 'dialogs.dart';

/// Short task-based setup: prepare, discover/connect, then show actual success.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final bool managing;
  late final bool openedInDemo;
  late final bool namingRequired;
  final scooterName = TextEditingController();
  bool savingName = false;
  bool closing = false;
  late int step;
  late int messageBaseline;
  bool connectionLost = false;
  @override
  void initState() {
    super.initState();
    managing =
        widget.controller.ready &&
        (widget.controller.isDemo || !widget.controller.setupNamePending);
    namingRequired = !widget.controller.setupComplete;
    openedInDemo = widget.controller.isDemo;
    step = !managing && widget.controller.ready
        ? 2
        : !managing && widget.controller.saved != null
        ? 1
        : 0;
    if (step == 2) _suggestName();
    messageBaseline = widget.controller.messageRevision;
    unawaited(widget.controller.markSetupSeen());
    widget.controller.addListener(_onChange);
    if (step == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  void _onChange() {
    if (managing || !mounted) return;
    if (widget.controller.ready && step < 2) {
      _suggestName();
      setState(() {
        step = namingRequired ? 2 : 3;
        connectionLost = false;
      });
    } else if (!widget.controller.ready && step >= 2) {
      setState(() {
        step = 1;
        connectionLost = true;
      });
    }
  }

  void _suggestName() {
    if (scooterName.text.isNotEmpty) return;
    final c = widget.controller;
    scooterName.text = c.model?.fallback == false
        ? c.model!.name
        : 'My scooter';
  }

  Future<void> _saveName() async {
    if (scooterName.text.trim().isEmpty || savingName) return;
    final c = widget.controller, deviceId = widget.controller.connectedId;
    setState(() => savingName = true);
    await c.finishSetupWithName(scooterName.text);
    if (!mounted) return;
    setState(() {
      savingName = false;
      if (c.ready && c.connectedId == deviceId && c.setupComplete) step = 3;
    });
  }

  void _search() {
    setState(() {
      step = 1;
      connectionLost = false;
      messageBaseline = widget.controller.messageRevision;
    });
    unawaited(widget.controller.scan());
  }

  void _connect(SavedScooter device) {
    setState(() {
      connectionLost = false;
      messageBaseline = widget.controller.messageRevision;
    });
    unawaited(
      widget.controller.connect(device, nameDuringSetup: namingRequired),
    );
  }

  Future<void> _chooseProtocol(NearbyScooter device) async {
    final candidates = widget.controller.registry.matching(device);
    if (candidates.isEmpty) return;
    final id = candidates.length == 1
        ? candidates.single.id
        : await showAppDialog<String>(
            context: context,
            builder: (context) => AppDialog(
              title: const Text('Choose scooter connection'),
              icon: Icons.bluetooth_rounded,
              content: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final candidate in candidates)
                      ListTile(
                        title: Text(candidate.label),
                        onTap: () => Navigator.pop(context, candidate.id),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
    if (id != null && mounted) {
      _connect(
        SavedScooter(
          device.id,
          device.name,
          advertisedName: device.name,
          protocolId: id,
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    scooterName.dispose();
    if (widget.controller.phase == LinkPhase.connecting) {
      unawaited(widget.controller.disconnect());
    } else {
      unawaited(widget.controller.stopScan());
    }
    super.dispose();
  }

  Future<void> _help() => showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: const Text('Connection help'),
      icon: Icons.help_outline_rounded,
      content: const Text(
        'Keep your scooter switched on and nearby. Disconnect it from other phones or the original app.\n\nIf Bluetooth access was denied, allow it in this app’s phone settings, then search again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            final opened = await openAppSettings();
            if (!opened && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Open your phone settings to allow Bluetooth access.',
                  ),
                ),
              );
            }
          },
          child: const Text('Open app settings'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final searching = c.phase == LinkPhase.scanning;
      final connecting = c.phase == LinkPhase.connecting;
      final error = c.messageRevision > messageBaseline
          ? c.message
          : connectionLost
          ? 'The scooter disconnected. Keep it nearby and try again.'
          : null;
      Widget content;
      Widget actions;
      if (managing) {
        final demo = closing ? openedInDemo : c.isDemo;
        final connected = closing || c.ready;
        content = _SetupContent(
          icon: demo
              ? Icons.science_outlined
              : Icons.bluetooth_connected_rounded,
          title: demo
              ? 'Demo Mode'
              : connected
              ? 'Scooter connected'
              : 'Disconnected',
          description: demo
              ? 'Sample readings are shown. No scooter is connected.'
              : connected
              ? c.scooterName
              : 'Connect again to view your scooter.',
        );
        actions = FilledButton(
          onPressed: closing
              ? null
              : () async {
                  setState(() => closing = true);
                  await c.disconnect();
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(
            demo
                ? 'Exit Demo Mode'
                : connected
                ? 'Disconnect'
                : 'Done',
          ),
        );
      } else if (step == 0) {
        content = const _SetupContent(
          icon: Icons.bluetooth_rounded,
          title: 'Get ready to connect',
          description: 'Keep your scooter switched on and within a few metres of your phone.',
          child: Column(
            children: [
              _SetupRow(
                icon: Icons.power_settings_new_rounded,
                title: 'Turn on your scooter',
                subtitle: 'Leave it stationary during setup.',
              ),
              _SetupRow(
                icon: Icons.phonelink_ring_outlined,
                title: 'Connect one phone at a time',
                subtitle: 'Disconnect other phones or the original app.',
              ),
              _SetupRow(
                icon: Icons.bluetooth_searching_rounded,
                title: 'Find your scooter',
                subtitle: 'Your phone will ask for Bluetooth access when the search starts.',
              ),
            ],
          ),
        );
        actions = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _search,
              child: const Text('Find my scooter'),
            ),
            TextButton(
              onPressed: () async {
                await widget.controller.startDemo();
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Try Demo Mode'),
            ),
          ],
        );
      } else if (step == 1) {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              connecting ? 'Connecting…' : 'Choose your scooter',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              connecting
                  ? 'Keep ${c.scooterName} nearby while the connection is prepared.'
                  : 'Select your scooter from the nearby devices below.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (connecting)
              Panel(
                child: Row(
                  children: [
                    const ConnectionProgress(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        c.scooterName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      searching ? 'Searching nearby…' : 'Nearby scooters',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (searching) const ConnectionProgress(),
                ],
              ),
              const SizedBox(height: 12),
              if (c.nearby.isEmpty)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        searching
                            ? 'Waiting for a scooter'
                            : 'No scooters found',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        searching
                            ? 'Keep your scooter switched on. It will appear here when detected.'
                            : 'Check that your scooter is on and not connected to another phone, then search again.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final device in c.nearby)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth_rounded),
                      title: Text(device.name),
                      subtitle: Text(
                        c.registry
                            .matching(device)
                            .map((p) => p.label)
                            .join(' / '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _chooseProtocol(device),
                    ),
                  ),
                ),
              if (c.saved != null) ...[
                const SectionLabel('Saved scooter'),
                Panel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(c.saved!.name),
                    subtitle: const Text('Connect again'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _connect(c.saved!),
                  ),
                ),
              ],
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _help,
              icon: const Icon(Icons.help_outline_rounded, size: 20),
              label: const Text('Connection help'),
            ),
          ],
        );
        actions = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connecting)
              OutlinedButton(
                onPressed: c.disconnect,
                child: const Text('Cancel connection'),
              )
            else if (searching)
              OutlinedButton(
                onPressed: c.stopScan,
                child: const Text('Stop search'),
              )
            else
              FilledButton(
                onPressed: _search,
                child: const Text('Search again'),
              ),
            TextButton(
              onPressed: () async {
                if (connecting) {
                  await c.disconnect();
                } else {
                  await c.stopScan();
                }
                if (mounted) setState(() => step = 0);
              },
              child: const Text('Back'),
            ),
          ],
        );
      } else if (step == 2) {
        content = _SetupContent(
          icon: Icons.edit_outlined,
          title: 'Name your scooter',
          description: 'Choose the name you’ll see in the app. You can change it later in Settings.',
          child: TextField(
            key: const ValueKey('setup-scooter-name'),
            controller: scooterName,
            autofocus: true,
            enabled: !savingName,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Scooter name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _saveName(),
          ),
        );
        actions = FilledButton(
          onPressed: savingName || scooterName.text.trim().isEmpty
              ? null
              : _saveName,
          child: Text(savingName ? 'Saving…' : 'Save name'),
        );
      } else {
        content = _SetupContent(
          icon: Icons.check_circle_outline_rounded,
          title: 'Scooter connected',
          description: c.scooterName,
          child: const Text(
            'You’re ready to view the dashboard. Live readings appear as your scooter reports them.',
          ),
        );
        actions = FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open dashboard'),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(managing ? 'Connection' : 'Set up scooter'),
          leading: IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close setup',
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Column(
                  children: [
                    if (!managing) ...[
                      _SetupProgress(step),
                      const SizedBox(height: 24),
                    ],
                    Expanded(
                      child: StateTransition(
                        child: ListView(
                          key: ValueKey(managing ? 'connection-details' : step),
                          padding: EdgeInsets.zero,
                          children: [content],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: actions),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SetupProgress extends StatelessWidget {
  const _SetupProgress(this.step);
  final int step;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Setup',
    value: 'Step ${step + 1} of 4',
    child: ExcludeSemantics(
      child: Row(
        children: [
          for (var index = 0; index < 4; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index < 3 ? 8 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.duration(context, AppMotion.feedback),
                      curve: AppMotion.curve,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: index <= step
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      const ['Prepare', 'Connect', 'Name', 'Ready'][index],
                      style: TextStyle(
                        fontSize: 12,
                        color: index == step
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _SetupContent extends StatelessWidget {
  const _SetupContent({
    required this.icon,
    required this.title,
    required this.description,
    this.child,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          size: 30,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 24),
      Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        description,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      if (child != null) ...[const SizedBox(height: 24), child!],
    ],
  );
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
