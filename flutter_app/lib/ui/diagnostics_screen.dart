import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/hex_bytes.dart';
import '../core/telemetry.dart';
import '../services/scooter_controller.dart';
import 'widgets.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final code = TextEditingController();
  final data = TextEditingController();
  @override
  void dispose() {
    code.dispose();
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final state = controller.telemetry;
      final entries = controller.logs;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Diagnostics'),
          actions: [
            IconButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: controller.exportLog()),
              ),
              tooltip: 'Copy frame log',
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              onPressed: controller.clearLog,
              tooltip: 'Clear frame log',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: pageInsets(context),
            children: [
              const PageHeading(
                'Connection status',
                'Advanced tools for checking scooter communication.',
              ),
              Panel(
                child: SelectableText(
                  'Model: ${controller.modelLabel}\n'
                  'Protocol: ${controller.protocolLabel}\n'
                  'Advertised: ${controller.evidence?.advertisedName ?? 'unknown'}\n'
                  'GATT: ${controller.evidence?.layoutId ?? 'unknown'}\n'
                  'Firmware: ${controller.evidence?.firmware ?? {}}\n'
                  'Lock: ${state.locked ?? 'unknown'} · Gear: ${state.gear ?? 'unknown'}\n'
                  'Kick start: ${state.flag(Reading.kickStart) ?? 'unknown'}\n'
                  'Headlight: ${state.flag(Reading.headlight) ?? 'unknown'} · Cruise: ${state.flag(Reading.cruise) ?? 'unknown'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.8,
                  ),
                ),
              ),
              const SectionLabel('Dashboard work mode'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Model-dependent register, separate from the ride gear.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var mode = 1; mode <= 3; mode++)
                          ChoiceChip(
                            label: Text('Mode $mode'),
                            selected: state.integer(Reading.workMode) == mode,
                            onSelected:
                                controller.canControl &&
                                    controller.supportsControl(
                                      ScooterControl.workMode,
                                    ) &&
                                    !controller.pending(ScooterControl.workMode)
                                ? (_) => controller.setWorkMode(mode)
                                : null,
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed:
                          controller.ready &&
                              controller.supportsControl(
                                ScooterControl.workMode,
                              )
                          ? controller.queryWorkMode
                          : null,
                      child: const Text('Read work mode'),
                    ),
                  ],
                ),
              ),
              const SectionLabel('Raw command'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Code · decimal',
                        hintText: '171',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: data,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Data · hexadecimal bytes',
                        hintText: 'AD',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          !controller.canControl ||
                              !controller.supportsControl(ScooterControl.raw)
                          ? null
                          : () {
                              try {
                                final opcode = int.tryParse(code.text);
                                if (opcode == null ||
                                    opcode < 0 ||
                                    opcode > 255) {
                                  throw const FormatException(
                                    'Use a command code from 0 to 255.',
                                  );
                                }
                                final bytes = HexBytes.parse(data.text);
                                controller.sendRaw(opcode, bytes);
                              } catch (error) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: Text(
                        controller.isDemo ? 'Simulate command' : 'Send command',
                      ),
                    ),
                  ],
                ),
              ),
              SectionLabel(
                'Frame log',
                trailing: Text(
                  '${entries.length} / 240',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (entries.isEmpty)
                const Panel(
                  child: Text(
                    'Frames appear here when you connect or use Demo Mode.',
                  ),
                ),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.direction}  ${entry.at.toLocal().toString().substring(11, 19)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          entry.message,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
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
    },
  );
}
