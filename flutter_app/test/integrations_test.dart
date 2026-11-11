import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/ble/ble_models.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/integrations/protocol_registry.dart';
import 'package:escooter_control/integrations/vicont/vicont_protocol.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/alternate_protocol.dart';
import 'support/fake_transport.dart';

void main() {
  test(
    'rapid connection requests reserve one session before disconnect yields',
    () async {
      final transport = FakeTransport();
      final controller = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(controller.dispose);
      final first = controller.connect(const SavedScooter('first', 'VC_First'));
      final second = controller.connect(
        const SavedScooter('second', 'VC_Second'),
      );
      await Future.wait([first, second]);
      expect(controller.ready, isTrue);
      expect(controller.connectedId, 'first');
      expect(transport.connections, 1);
      expect(
        transport.writes
            .where((frame) => frame.length == 7 && frame[4] == 1)
            .length,
        2,
      );
    },
  );
  test('GATT write modes require the requested characteristic capability', () {
    const service = GattServiceInfo('1234', [
      GattCharacteristicInfo('1235', notify: true, writeWithoutResponse: true),
    ]);
    const acknowledged = BleConnectionProfile(
      layouts: [
        GattLayout(
          id: 'response',
          service: '1234',
          notify: '1235',
          writeMode: GattWriteMode.withResponse,
        ),
      ],
    );
    expect(selectGattLayout([service], acknowledged), isNull);
    const command = BleConnectionProfile(
      layouts: [
        GattLayout(
          id: 'command',
          service: '1234',
          notify: '1235',
          writeMode: GattWriteMode.withoutResponse,
        ),
      ],
    );
    expect(
      selectGattLayout([service], command)?.writeMode,
      GattWriteMode.withoutResponse,
    );
  });
  test(
    'a second protocol scans, connects, decodes and confirms its own commands',
    () async {
      final transport = FakeTransport();
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        registry: ProtocolRegistry([VicontProtocol(), AlternateProtocol()]),
      );
      addTearDown(c.dispose);
      await c.scan();
      transport.advertisements.add(
        const NearbyScooter('second', 'OTHER scooter', -42),
      );
      transport.advertisements.add(
        const NearbyScooter('original', 'VC_Test', -50),
      );
      expect(c.nearby.length, 2);
      await c.connect(const SavedScooter('second', 'OTHER scooter'));
      expect(c.ready, isTrue);
      expect(c.protocolId, 'test-alternate');
      expect(transport.lastProfile!.layouts.single.writeService, '2345');
      expect(transport.writes, [
        [0x12, 0x34],
      ]);
      expect(c.supports(Feature.headlight), isTrue);
      expect(c.supports(Feature.kickStart), isFalse);
      transport.received.add([0xb1, 70, 12, 0]);
      expect(c.telemetry[Reading.speed], 12);
      transport.onWrite = (bytes) {
        if (bytes[0] == 0x7e) transport.received.add([0xb1, 70, 12, bytes[1]]);
      };
      expect(
        await c.toggle(
          ScooterControl.headlight,
          Reading.headlight,
          'Headlight',
        ),
        isTrue,
      );
      expect(transport.writes.last, [0x7e, 1]);
      final count = transport.writes.length;
      expect(await c.setConfig(ScooterControl.maxSpeed, 40), isFalse);
      await c.sendRaw(51, [1]);
      expect(transport.writes.length, count);
      await c.connect(const SavedScooter('original', 'VC_Test'));
      expect(c.protocolId, 'vicont');
      expect(transport.writes.skip(count).take(2), [
        [250, 175, 165, 90, 1, 0, 91],
        [250, 175, 165, 250, 1, 0, 91],
      ]);
      expect(c.telemetry[Reading.speed], isNull);
    },
  );
  test(
    'ambiguous or unknown protocols never prepare or send a handshake',
    () async {
      final transport = FakeTransport();
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        registry: ProtocolRegistry([
          VicontProtocol(),
          AlternateProtocol(prefix: 'VC_'),
        ]),
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('a', 'VC_Test'));
      expect(c.message, contains('More than one'));
      await c.connect(const SavedScooter('b', 'Unknown'));
      expect(c.message, contains('No Bluetooth integration'));
      expect(transport.prepares, 0);
      expect(transport.writes, isEmpty);
    },
  );
  test('GATT selection supports separate services and rejects missing write characteristics', () {
    final profile = AlternateProtocol().connection;
    const services = [
      GattServiceInfo('1234', [GattCharacteristicInfo('1235', notify: true)]),
      GattServiceInfo('2345', [
        GattCharacteristicInfo('2346', writeWithoutResponse: true),
      ]),
    ];
    final selected = selectGattLayout(services, profile)!;
    expect(selected.notifyService, '1234');
    expect(selected.writeService, '2345');
    expect(selectGattLayout(services.take(1).toList(), profile), isNull);
    expect(
      selectGattLayout(const [
        GattServiceInfo('1234', [GattCharacteristicInfo('1235', notify: true)]),
        GattServiceInfo('2345', [
          GattCharacteristicInfo('9999', writeWithoutResponse: true),
        ]),
      ], profile),
      isNull,
    );
    expect(
      selectGattLayout(const [
        GattServiceInfo('FFF0', [
          GattCharacteristicInfo(
            'FFF1',
            notify: true,
            writeWithoutResponse: true,
          ),
        ]),
      ], VicontProtocol().connection)!.layoutId,
      'fff0-fff1',
    );
  });
  test('duplicate advertisements do not rebuild discovery and significant RSSI changes reorder it', () async {
    final t = FakeTransport();
    final c = ScooterController(
      transport: t,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await c.scan();
    var changes = 0;
    c.addListener(() => changes++);
    t.advertisements.add(const NearbyScooter('a', 'VC_Test', -40));
    for (var i = 0; i < 200; i++) {
      t.advertisements.add(const NearbyScooter('a', 'VC_Test', -41));
    }
    expect(changes, 1);
    t.advertisements.add(const NearbyScooter('b', 'VC_Other', -45));
    t.advertisements.add(const NearbyScooter('a', 'VC_Test', -70));
    expect(c.nearby.first.id, 'b');
    expect(changes, 3);
  });
  test(
    'a burst of telemetry is processed fully with one scheduled UI update',
    () async {
      final t = FakeTransport();
      final c = ScooterController(
        transport: t,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        telemetryRefreshInterval: const Duration(milliseconds: 5),
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('a', 'VC_Test'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      var changes = 0;
      c.addListener(() => changes++);
      for (var i = 0; i < 100; i++) {
        t.emit(16, [0x12, 0xfc, 0, 0, 0, i, 80]);
      }
      expect(c.telemetry[Reading.speed], 9.9);
      expect(changes, 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(changes, 1);
    },
  );
}
