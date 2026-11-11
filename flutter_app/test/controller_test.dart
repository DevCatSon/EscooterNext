import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/core/protocol.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/services/ble_transport.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/fake_transport.dart';

void main() {
  test(
    'a name save failure keeps first-time setup incomplete and retryable',
    () async {
      final prefs = _RejectingNameStore();
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: prefs,
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(
        const SavedScooter('test', 'VC_Test'),
        nameDuringSetup: true,
      );
      prefs.rejectNames = true;
      await c.finishSetupWithName('City ride');
      expect(c.setupNamePending, true);
      expect(c.setupComplete, false);
      expect(c.saved!.name, 'VC_Test');
      expect(prefs.read('setupNamePending'), 'true');
      expect(c.message, contains('could not be saved'));
      prefs.rejectNames = false;
      await c.finishSetupWithName('City ride');
      expect(c.setupComplete, true);
      expect(c.saved!.name, 'City ride');
    },
  );
  test('Find sends a one-shot locate request on every press', () async {
    final t = FakeTransport();
    t.onWrite = (bytes) {
      if (bytes[4] == 52) t.emit(52, [0]);
    };
    final c = ScooterController(
      transport: t,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await c.connect(const SavedScooter('test', 'VC_Test'));
    await c.findScooter();
    await c.findScooter();
    final locate = t.writes.where((bytes) => bytes[4] == 52).toList();
    expect(locate.map((bytes) => bytes[6]), [1, 1]);
    await c.disconnect();
    await c.findScooter();
    expect(t.writes.where((bytes) => bytes[4] == 52).length, 2);
  });
  test(
    'unfinished first-time naming survives restart and preserves BLE identity',
    () async {
      final prefs = MemoryPreferenceStore();
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: prefs,
        permissions: () async {},
      );
      await c.connect(
        const SavedScooter('test', 'VC_Test'),
        nameDuringSetup: true,
      );
      expect(c.setupComplete, false);
      expect(c.setupNamePending, true);
      expect(prefs.read('setupNamePending'), 'true');
      c.dispose();
      final next = ScooterController(
        transport: FakeTransport(),
        preferences: prefs,
        permissions: () async {},
      );
      addTearDown(next.dispose);
      expect(next.setupComplete, false);
      expect(next.setupNamePending, true);
      await next.connect(next.saved!);
      await next.finishSetupWithName('  City ride  ');
      expect(next.setupComplete, true);
      expect(next.setupNamePending, false);
      expect(next.saved!.name, 'City ride');
      expect(next.saved!.advertisedName, 'VC_Test');
      expect(SavedScooter.decode(prefs.read('scooter'))!.name, 'City ride');
      expect(prefs.read('setupNamePending'), 'false');
    },
  );
  late FakeTransport transport;
  late MemoryPreferenceStore prefs;
  late ScooterController controller;
  setUp(() {
    transport = FakeTransport();
    prefs = MemoryPreferenceStore();
    controller = ScooterController(
      transport: transport,
      preferences: prefs,
      permissions: () async {},
      confirmationTimeout: const Duration(milliseconds: 35),
    );
  });
  tearDown(() => controller.dispose());
  Future<void> live() async {
    await controller.connect(
      const SavedScooter('ios-or-android-id', 'VC test', protocolId: 'vicont'),
    );
    transport.status();
    await Future<void>.delayed(Duration.zero);
  }

  test('cancelling a permission-stage connection cannot overwrite a newer demo session', () async {
    final permission = Completer<void>();
    final localTransport = FakeTransport();
    final local = ScooterController(
      transport: localTransport,
      preferences: MemoryPreferenceStore(),
      permissions: () => permission.future,
    );
    final connecting = local.connect(
      const SavedScooter('cancelled', 'Old attempt', protocolId: 'vicont'),
    );
    await Future<void>.delayed(Duration.zero);
    await local.startDemo();
    permission.complete();
    await connecting;
    expect(local.isDemo, true);
    expect(local.ready, true);
    expect(localTransport.connections, 0);
    expect(local.saved, isNull);
    local.dispose();
  });

  test('binding acknowledgement matches the original client and is not repeated each heartbeat', () async {
    await live();
    transport.status(second: 0x41);
    await Future<void>.delayed(Duration.zero);
    final acknowledgements = transport.writes
        .where((data) => data[4] == 76)
        .toList();
    expect(acknowledgements.length, 1);
    expect(acknowledgements.single[6], 2);
    transport.status(second: 0x41);
    await Future<void>.delayed(Duration.zero);
    expect(transport.writes.where((data) => data[4] == 76).length, 1);
  });
  test(
    'corrupt status cannot change sync, controls or send binding writes',
    () async {
      await live();
      final before = controller.telemetry;
      final lastReceived = controller.lastReceived;
      final writeCount = transport.writes.length;
      final bad = incoming(17, [0x23, 0x41, 0, 0, 0, 0], zt: 0x91);
      bad[bad.length - 1] ^= 0xff;
      transport.received.add(bad);
      await Future<void>.delayed(Duration.zero);
      expect(controller.telemetry, same(before));
      expect(controller.lastReceived, lastReceived);
      expect(transport.writes.length, writeCount);
      transport.status(flags: 0x23);
      expect(controller.telemetry.flag(Reading.kickStart), true);
    },
  );
  test('corrupt status cannot confirm a pending kick-start command', () async {
    await live();
    final result = controller.toggle(
      ScooterControl.kickStart,
      Reading.kickStart,
      'Kick start',
    );
    await Future<void>.delayed(Duration.zero);
    final bad = incoming(17, [0x23, 1, 0, 0, 0, 0])..last = 0;
    transport.received.add(bad);
    expect(controller.pending(ScooterControl.kickStart), true);
    expect(await result, false);
    expect(controller.telemetry.flag(Reading.kickStart), false);
  });
  test(
    'speed requests above 31 are clamped before reaching the scooter',
    () async {
      await live();
      expect(await controller.setConfig(ScooterControl.maxSpeed, 50), true);
      expect(transport.writes.last[4], 60);
      expect(transport.writes.last[6], 31);
      expect(controller.telemetry[Reading.maxSpeed], 31);
    },
  );
  test(
    'a pending reconnect retains the last configured GATT details in exports',
    () async {
      final t = _PausedPrepareTransport();
      final c = ScooterController(
        transport: t,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('device', 'VC_Test'));
      for (var i = 0; i < 250; i++) {
        t.status();
      }
      t.prepareGate = Completer<void>();
      final connecting = c.connect(c.saved!);
      await Future<void>.delayed(Duration.zero);
      final log = jsonDecode(c.exportLog()) as Map;
      expect(log['previousConnection']['layout'], 'fee0-fee2');
      expect(log['previousConnection']['write'], 'fee2');
      expect(log['connection']['layout'], isNull);
      await c.disconnect();
      t.prepareGate!.complete();
      await connecting;
    },
  );

  test('demo uses no permission prompts, scan, connection or writes and is never saved', () async {
    await controller.startDemo();
    await controller.toggle(
      ScooterControl.kickStart,
      Reading.kickStart,
      'Kick start',
    );
    await controller.setConfig(ScooterControl.maxSpeed, 31);
    await controller.setMiles(true);
    await controller.readSettings();
    expect(transport.prepares, 0);
    expect(transport.connections, 0);
    expect(transport.writes, isEmpty);
    expect(controller.telemetry[Reading.maxSpeed], 31);
    expect(controller.telemetry.miles, true);
    expect(controller.telemetry.flag(Reading.kickStart), false);
    expect(prefs.read('scooter'), isNull);
  });
  test('connection uses both literal handshakes and remembers opaque iOS-style ids', () async {
    await live();
    expect(transport.writes.take(2).map(Protocol.hex), [
      'FAAFA55A01005B',
      'FAAFA5FA01005B',
    ]);
    expect(controller.saved?.id, 'ios-or-android-id');
    expect(controller.ready, true);
    expect(controller.telemetry[Reading.trip], 4.7);
    await controller.rename('Morning ride');
    expect(SavedScooter.decode(prefs.read('scooter'))?.name, 'Morning ride');
  });
  test('kick-start UI waits for status instead of treating a code-53 ack as success', () async {
    await live();
    final result = controller.toggle(
      ScooterControl.kickStart,
      Reading.kickStart,
      'Kick start',
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.pending(ScooterControl.kickStart), true);
    expect(controller.telemetry.flag(Reading.kickStart), false);
    expect(transport.writes.last[6], 2);
    transport.emit(53, [0]);
    expect(controller.pending(ScooterControl.kickStart), true);
    expect(controller.telemetry.flag(Reading.kickStart), false);
    transport.status(flags: 0x23);
    expect(await result, true);
    expect(controller.pending(ScooterControl.kickStart), false);
    expect(controller.telemetry.flag(Reading.kickStart), true);
  });
  test('unconfirmed kick-start requests leave the reported value intact and explain failure', () async {
    await live();
    expect(
      await controller.toggle(
        ScooterControl.kickStart,
        Reading.kickStart,
        'Kick start',
      ),
      false,
    );
    expect(controller.telemetry.flag(Reading.kickStart), false);
    expect(controller.message, contains("wasn't confirmed"));
    expect(controller.message, contains('firmware'));
  });
  test(
    'rapid repeated pending toggles produce only one wire command',
    () async {
      await live();
      final first = controller.toggle(
        ScooterControl.kickStart,
        Reading.kickStart,
        'Kick start',
      );
      final second = controller.toggle(
        ScooterControl.kickStart,
        Reading.kickStart,
        'Kick start',
      );
      await Future<void>.delayed(Duration.zero);
      expect(await second, false);
      expect(transport.writes.where((data) => data[4] == 53).length, 1);
      transport.status(flags: 0x23);
      expect(await first, true);
    },
  );
  test('a silent tuning timeout restores the actual reading without a follow-up reply', () async {
    await live();
    transport.emit(60, [25]);
    transport.replyToConfig = false;
    final before = controller.configRevision;
    final future = controller.setConfig(ScooterControl.maxSpeed, 31);
    expect(controller.pending(ScooterControl.maxSpeed), true);
    expect(controller.telemetry[Reading.maxSpeed], 25);
    expect(await future, false);
    expect(controller.pending(ScooterControl.maxSpeed), false);
    expect(controller.telemetry[Reading.maxSpeed], 25);
    expect(controller.configRevision, greaterThan(before));
    expect(controller.tuningNotice, contains("wasn't confirmed"));
  });
  test('speed readback shows a controller restriction rather than assuming 31 was accepted', () async {
    await live();
    transport.replyToConfig = false;
    transport.onWrite = (data) {
      if (data[4] == 60) transport.emit(60, [25]);
    };
    expect(await controller.setConfig(ScooterControl.maxSpeed, 31), true);
    expect(controller.telemetry[Reading.maxSpeed], 25);
    expect(controller.tuningNotice, contains('Requested 31'));
  });
  test('disconnect cancels pending commands and resets all connection-scoped readings', () async {
    await live();
    final future = controller.toggle(
      ScooterControl.kickStart,
      Reading.kickStart,
      'Kick start',
    );
    await Future<void>.delayed(Duration.zero);
    await controller.disconnect();
    expect(await future, false);
    expect(controller.phase, LinkPhase.idle);
    expect(controller.telemetry.values, isEmpty);
    expect(controller.pending(ScooterControl.kickStart), false);
    transport.status(flags: 0x23);
    expect(controller.telemetry.values, isEmpty);
  });
  test('unknown status and unavailable gears cannot produce writes', () async {
    await controller.connect(
      const SavedScooter('id', 'Scooter', protocolId: 'vicont'),
    );
    await Future<void>.delayed(Duration.zero);
    final before = transport.writes.length;
    expect(
      await controller.toggle(
        ScooterControl.kickStart,
        Reading.kickStart,
        'Kick start',
      ),
      false,
    );
    transport.emit(18, [0, 0, 1, 1, 0, 0, 1, 1, 1]);
    expect(await controller.setGear(3), false);
    expect(transport.writes.length, before);
  });
  test('scan filters known prefixes, sorts signal strength, and keeps iOS uuids opaque', () async {
    await controller.scan();
    transport.advertisements.add(const NearbyScooter('uuid-1', 'VC-Test', -70));
    transport.advertisements.add(
      const NearbyScooter('uuid-2', 'e-s Test', -40),
    );
    transport.advertisements.add(
      const NearbyScooter('other', 'Headphones', -20),
    );
    expect(controller.nearby.map((e) => e.id), ['uuid-2', 'uuid-1']);
    await controller.stopScan();
    expect(controller.phase, LinkPhase.idle);
  });
  test(
    'locked scooter blocks tuning while still accepting an unlock request',
    () async {
      await live();
      transport.status(second: 3);
      expect(await controller.setConfig(ScooterControl.maxSpeed, 40), false);
      expect(transport.writes.where((data) => data[4] == 60), isEmpty);
      final unlock = controller.toggleLock();
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes.last[4], 51);
      expect(transport.writes.last[6], 1);
      transport.status(second: 1);
      expect(await unlock, true);
    },
  );
  test(
    'a reported lock cancels control writes still waiting in the queue',
    () async {
      await live();
      transport.onWrite = (bytes) {
        if (bytes[4] == 60) transport.status(second: 0x43);
      };
      final speed = controller.setConfig(ScooterControl.maxSpeed, 25);
      final brake = controller.setConfig(ScooterControl.brake, 5);
      final raw = controller.sendRaw(65, [1, 0]);
      expect(await speed, isTrue);
      expect(await brake, isFalse);
      await raw;
      expect(controller.telemetry.locked, isTrue);
      expect(transport.writes.where((bytes) => bytes[4] == 63), isEmpty);
      expect(transport.writes.where((bytes) => bytes[4] == 65), isEmpty);
    },
  );
  test('theme, feature visibility and forget are persisted without saving demo identity', () async {
    await live();
    await controller.setAppearance(AppAppearance.dark);
    await controller.setFeature(Feature.ambient, true);
    expect(prefs.read('appearance'), 'dark');
    expect(
      controller.database.overrides('ios-or-android-id')[Feature.ambient],
      true,
    );
    await controller.startDemo();
    await controller.rename('Demo only');
    expect(SavedScooter.decode(prefs.read('scooter'))?.name, 'VC test');
    await controller.forget();
    expect(prefs.read('scooter'), isNull);
    expect(controller.ready, false);
  });
}

class _PausedPrepareTransport extends FakeTransport {
  Completer<void>? prepareGate;
  @override
  Future<void> prepare() async {
    await super.prepare();
    await prepareGate?.future;
  }
}

class _RejectingNameStore extends MemoryPreferenceStore {
  bool rejectNames = false;
  @override
  Future<void> write(String key, String? value) async {
    if (key == 'scooter' && rejectNames) {
      throw StateError('Storage unavailable');
    }
    await super.write(key, value);
  }
}
