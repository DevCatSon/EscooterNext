import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/scooter_controller.dart';
import 'widgets.dart';
import 'dialogs.dart';

class ScooterModelsScreen extends StatelessWidget {
  const ScooterModelsScreen({required this.controller, super.key});
  final ScooterController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final current = controller.connectedId ?? controller.saved?.id;
      final pinned = current == null
          ? null
          : controller.database.profileId(current);
      final selectable = controller.protocolId != null && !controller.isDemo;
      return Scaffold(
        appBar: AppBar(title: const Text('Scooter models')),
        body: SafeArea(
          child: ListView(
            padding: pageInsets(context),
            children: [
              PageHeading(
                controller.modelLabel,
                controller.modelAmbiguous
                    ? 'Several models match. Choose yours below.'
                    : controller.model?.fallback == false
                    ? 'Features and vehicle image follow this model.'
                    : 'Connect and save your model to build your local catalogue.',
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ScooterArt(
                        height: 150,
                        artwork: controller.artwork,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      controller.protocolLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (controller.evidence?.advertisedName.isNotEmpty == true)
                      Text(controller.evidence!.advertisedName),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Save this model'),
                        onPressed: controller.ready && !controller.isDemo
                            ? () async {
                                final result =
                                    await showAppDialog<(String, String)>(
                                      context: context,
                                      builder: (_) => _SaveModelDialog(
                                        initialName:
                                            controller.model?.fallback == false
                                            ? controller.model!.name
                                            : '',
                                        initialArtwork: controller.artwork,
                                      ),
                                    );
                                if (result != null) {
                                  await controller.saveCurrentModel(
                                    result.$1,
                                    result.$2,
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SectionLabel('Model selection'),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Automatic matching'),
                      subtitle: const Text(
                        'Use the Bluetooth name, services and firmware',
                      ),
                      trailing: pinned == null
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: selectable
                          ? () => controller.selectModel(null)
                          : null,
                    ),
                    for (final model in controller.models.where(
                      (m) => m.protocolId == controller.protocolId,
                    )) ...[
                      const Divider(),
                      ListTile(
                        title: Text(model.name),
                        subtitle: Text(model.source),
                        trailing: pinned == model.id
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: selectable
                            ? () => controller.selectModel(model.id)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
              const SectionLabel('Local records'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${controller.database.observationCount} scooter observations saved on this phone.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Model records store your chosen features and vehicle image. You can review feature support in Settings.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy model data'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: controller.database.exportJson()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Local model data copied.'),
                            ),
                          );
                        }
                      },
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

class _SaveModelDialog extends StatefulWidget {
  const _SaveModelDialog({
    required this.initialName,
    required this.initialArtwork,
  });
  final String initialName, initialArtwork;
  @override
  State<_SaveModelDialog> createState() => _SaveModelDialogState();
}

class _SaveModelDialogState extends State<_SaveModelDialog> {
  late final name = TextEditingController(text: widget.initialName);
  late String artwork = widget.initialArtwork;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('Save scooter model'),
    icon: Icons.bookmark_add_outlined,
    content: SingleChildScrollView(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uses this scooter\'s Bluetooth name and your current feature selection.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              maxLength: 48,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Model name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text('Vehicle image'),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in [
                  ('assets/scooter.png', 'Scooter render'),
                  ('icon:scooter', 'Scooter symbol'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: artwork == value,
                    onSelected: (_) => setState(() => artwork = value),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (name.text.trim(), artwork)),
        child: const Text('Save model'),
      ),
    ],
  );
}
