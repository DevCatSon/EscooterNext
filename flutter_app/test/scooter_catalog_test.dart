import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/catalog/local_scooter_database.dart';
import 'package:escooter_control/catalog/scooter_catalog.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/fake_transport.dart';

const testModel = ScooterModel(
  id: 'fixture-model',
  name: 'Fixture commuter',
  protocolId: 'vicont',
  namePrefixes: ['VC_'],
  firmware: {'controllerHardware': 2, 'controllerSoftware': 27},
  requiredServices: ['fee0'],
  features: {Feature.headlight, Feature.ambient},
  artwork: 'icon:scooter',
  source: 'Synthetic test catalogue',
);

void main() {
  test('malformed local records do not prevent startup', () async {
    final preferences = MemoryPreferenceStore();
    for (final source in [
      'not JSON',
      '{"schemaVersion":1,"models":42,"devices":false,"observations":[]}',
      '{"schemaVersion":99}',
    ]) {
      await preferences.write('scooter.database', source);
      final database = LocalScooterDatabase(preferences);
      expect(database.models, isEmpty);
      expect(database.observationCount, 0);
    }
  });
  test(
    'the bundled catalogue includes the owner-reported G30 and family fallback',
    () {
      final catalog = ScooterCatalog.fromJson(
        File('assets/scooter_catalog.json').readAsStringSync(),
      );
      expect(catalog.byId('vicont-generic')!.fallback, isTrue);
      expect(catalog.byId('vicont-generic')!.source, contains('unconfirmed'));
      final g30 = catalog.byId('gyrocopters-g30')!;
      expect(g30.name, 'Gyrocopters G30');
      expect(g30.artwork, 'assets/models/gyrocopters-g30.png');
      expect(File(g30.artwork).existsSync(), isTrue);
      expect(catalog.byId('vicont-generic')!.artwork, 'assets/scooter.png');
      expect(g30.fallback, false);
      const firmware = {
        'instrumentHardware': 104,
        'instrumentSoftware': 37,
        'controllerHardware': 10,
        'controllerSoftware': 44,
      };
      expect(
        catalog
            .match(
              const ScooterEvidence(
                protocolId: 'vicont',
                advertisedName: 'SN_TEST',
                firmware: firmware,
              ),
            )
            .model
            ?.id,
        g30.id,
      );
      expect(
        catalog
            .match(
              const ScooterEvidence(
                protocolId: 'vicont',
                advertisedName: 'SN_OTHER',
              ),
            )
            .model
            ?.id,
        'vicont-generic',
      );
      expect(
        catalog
            .match(
              const ScooterEvidence(
                protocolId: 'vicont',
                advertisedName: 'VC_OTHER',
                firmware: firmware,
              ),
            )
            .model
            ?.id,
        'vicont-generic',
      );
      expect(
        catalog
            .match(
              ScooterEvidence(
                protocolId: 'vicont',
                advertisedName: 'SN_OTHER',
                firmware: {...firmware, 'controllerSoftware': 45},
              ),
            )
            .model
            ?.id,
        'vicont-generic',
      );
      expect(
        () => ScooterCatalog.fromJson('{"schemaVersion":99,"models":[]}'),
        throwsFormatException,
      );
    },
  );
  test('model matching requires the protocol and all recorded constraints', () {
    final catalog = ScooterCatalog([testModel]);
    expect(
      catalog
          .match(
            const ScooterEvidence(
              protocolId: 'vicont',
              advertisedName: 'VC_Test',
            ),
          )
          .model,
      isNull,
    );
    expect(
      catalog
          .match(
            const ScooterEvidence(
              protocolId: 'other',
              advertisedName: 'VC_Test',
              services: ['fee0'],
              firmware: {'controllerHardware': 2, 'controllerSoftware': 27},
            ),
          )
          .model,
      isNull,
    );
    expect(
      catalog
          .match(
            const ScooterEvidence(
              protocolId: 'vicont',
              advertisedName: 'VC_Test',
              services: ['0000fee0-0000-1000-8000-00805f9b34fb'],
              firmware: {'controllerHardware': 2, 'controllerSoftware': 27},
            ),
          )
          .model
          ?.id,
      'fixture-model',
    );
  });
  test('equally specific models remain ambiguous instead of depending on file order', () {
    const a = ScooterModel(
      id: 'a',
      name: 'A',
      protocolId: 'vicont',
      namePrefixes: ['VC_'],
      features: {},
    );
    const b = ScooterModel(
      id: 'b',
      name: 'B',
      protocolId: 'vicont',
      namePrefixes: ['VC_'],
      features: {},
    );
    for (final order in [
      [a, b],
      [b, a],
    ]) {
      final match = ScooterCatalog(order).match(
        const ScooterEvidence(protocolId: 'vicont', advertisedName: 'VC_Test'),
      );
      expect(match.model, isNull);
      expect(match.ambiguous, isTrue);
    }
    expect(() => ScooterCatalog([a, a]), throwsFormatException);
  });
  test('firmware evidence selects artwork/features automatically and logs structured type data', () async {
    final t = FakeTransport();
    final p = MemoryPreferenceStore();
    final c = ScooterController(
      transport: t,
      preferences: p,
      permissions: () async {},
      catalog: ScooterCatalog([testModel]),
    );
    addTearDown(c.dispose);
    await c.connect(const SavedScooter('opaque-private-id', 'VC_Test'));
    expect(c.model, isNull);
    t.emit(18, [0, 0, 3, 18, 0, 0, 2, 27, 7]);
    expect(c.modelLabel, 'Fixture commuter');
    expect(c.artwork, 'icon:scooter');
    expect(c.supports(Feature.ambient), isTrue);
    expect(c.supports(Feature.cruise), isFalse);
    final entry = c.logs.firstWhere(
      (e) => e.fields['modelId'] == 'fixture-model',
    );
    expect(entry.direction, 'TYPE');
    expect((entry.fields['firmware'] as Map)['controllerSoftware'], 27);
    expect(entry.fields['gattLayout'], 'fee0-fee2');
    final logCount = c.logs.where((e) => e.direction == 'TYPE').length;
    t.emit(18, [0, 0, 3, 18, 0, 0, 2, 27, 7]);
    expect(c.logs.where((e) => e.direction == 'TYPE').length, logCount);
    await c.setFeature(Feature.ambient, false);
    t.emit(18, [0, 0, 3, 18, 0, 0, 2, 27, 7]);
    expect(c.supports(Feature.ambient), isFalse);
    await c.resetFeatures();
    expect(c.supports(Feature.ambient), isTrue);
    await c.rename('My nickname');
    expect(c.saved!.advertisedName, 'VC_Test');
    expect(c.evidence!.advertisedName, 'VC_Test');
    await Future<void>.delayed(Duration.zero);
    final db = LocalScooterDatabase(p);
    expect(db.observationCount, 1);
    expect(db.exportJson(), contains('fixture-model'));
    expect(db.exportJson(), isNot(contains('opaque-private-id')));
    expect(c.exportLog(), isNot(contains('opaque-private-id')));
    c.clearLog();
    expect(db.observationCount, 1);
  });
  test(
    'feature overrides stay with their scooter across switches and reconnects',
    () async {
      final t = FakeTransport();
      final p = MemoryPreferenceStore();
      final c = ScooterController(
        transport: t,
        preferences: p,
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('a', 'VC_A'));
      await c.setFeature(Feature.ambient, true);
      await c.setFeature(Feature.cruise, false);
      await c.connect(const SavedScooter('b', 'VC_B'));
      expect(c.supports(Feature.ambient), isFalse);
      expect(c.supports(Feature.cruise), isTrue);
      await c.connect(const SavedScooter('a', 'VC_A'));
      expect(c.supports(Feature.ambient), isTrue);
      expect(c.supports(Feature.cruise), isFalse);
      expect(c.database.overrides('a')[Feature.ambient], isTrue);
    },
  );
  test('legacy saved names and global feature choices migrate only to that scooter', () async {
    final p = MemoryPreferenceStore();
    await p.write('scooter', '{"id":"legacy","name":"Renamed scooter"}');
    await p.write('feature.ambient', 'true');
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: p,
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await c.connect(c.saved!);
    expect(c.ready, isTrue);
    expect(c.protocolId, 'vicont');
    expect(c.supports(Feature.ambient), isTrue);
    await c.connect(const SavedScooter('new', 'VC_New'));
    expect(c.supports(Feature.ambient), isFalse);
  });
  test('local model creation, explicit choice and automatic matching survive storage', () async {
    final p = MemoryPreferenceStore();
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: p,
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await c.connect(const SavedScooter('a', 'VC_A'));
    await c.saveCurrentModel('My local model', 'icon:scooter');
    final id = c.model!.id;
    expect(c.modelLabel, 'My local model');
    expect(c.artwork, 'icon:scooter');
    expect(LocalScooterDatabase(p).models.single.id, id);
    expect(c.database.profileId('a'), id);
    await c.selectModel(null);
    expect(c.database.profileId('a'), isNull);
    // Exact-name catalogue matching now finds the saved local model automatically.
    expect(c.model?.id, id);
    await c.rename('Different nickname');
    final saved = c.saved!;
    await c.disconnect();
    await c.connect(saved);
    expect(c.model?.id, id);
    expect(c.evidence!.advertisedName, 'VC_A');
    expect(c.scooterName, 'Different nickname');
    final count = c.database.observationCount;
    await c.startDemo();
    await c.saveCurrentModel('Demo is not a scooter', 'icon:scooter');
    expect(c.database.models.length, 1);
    expect(c.database.observationCount, count);
  });
  test('record writes serialize and exported JSON has a bounded observation collection', () async {
    final p = MemoryPreferenceStore();
    final db = LocalScooterDatabase(p);
    final writes = <Future<void>>[];
    for (var i = 0; i < 140; i++) {
      writes.add(
        db.observe(
          'id-$i',
          ScooterEvidence(protocolId: 'vicont', advertisedName: 'VC_$i'),
        ),
      );
    }
    await Future.wait(writes);
    final reloaded = LocalScooterDatabase(p);
    expect(reloaded.observationCount, 128);
    final json = jsonDecode(reloaded.exportJson()) as Map;
    expect(json['schemaVersion'], 1);
    expect((json['observations'] as List).length, 128);
    expect(reloaded.exportJson(), isNot(contains('id-139')));
  });
}
