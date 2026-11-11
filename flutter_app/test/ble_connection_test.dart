import 'dart:async';

import 'package:escooter_control/integrations/vicont/vicont_protocol.dart';
import 'package:escooter_control/services/ble_transport.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

class _Characteristic extends Fake implements Characteristic {
  _Characteristic(this.events);
  final List<String> events;
  final values = StreamController<List<int>>.broadcast();
  final writes = <bool>[];
  @override
  Uuid get id => Uuid.parse(normalizeUuid('fee2'));
  @override
  bool get isNotifiable => true;
  @override
  bool get isIndicatable => false;
  @override
  bool get isWritableWithResponse => true;
  @override
  bool get isWritableWithoutResponse => true;
  @override
  Stream<List<int>> subscribe() {
    events.add('subscribe');
    return values.stream;
  }

  @override
  Future<void> write(List<int> value, {bool withResponse = true}) async {
    events.add('write');
    writes.add(withResponse);
  }
}

class _Service extends Fake implements Service {
  _Service(this.characteristic);
  final _Characteristic characteristic;
  @override
  Uuid get id => Uuid.parse(normalizeUuid('fee0'));
  @override
  List<Characteristic> get characteristics => [characteristic];
}

class _Ble extends Fake implements FlutterReactiveBle {
  final events = <String>[];
  late final characteristic = _Characteristic(events);
  final connection = StreamController<ConnectionStateUpdate>.broadcast();
  Completer<int>? mtuGate;
  bool rejectMtu = false;
  bool autoConnect = true;
  bool rejectConnection = false;
  bool rejectDiscovery = false;
  int connects = 0;
  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    connects++;
    if (rejectConnection) throw StateError('Native connection failed');
    if (autoConnect) {
      scheduleMicrotask(
        () => connection.add(
          ConnectionStateUpdate(
            deviceId: id,
            connectionState: DeviceConnectionState.connected,
            failure: null,
          ),
        ),
      );
    }
    return connection.stream;
  }

  @override
  Future<void> discoverAllServices(String deviceId) async {
    events.add('discover');
    if (rejectDiscovery) throw StateError('Discovery failed');
  }

  @override
  Future<List<Service>> getDiscoveredServices(String deviceId) async => [
    _Service(characteristic),
  ];
  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async {
    events.add('mtu:$mtu');
    if (rejectMtu) throw StateError('MTU request rejected');
    return mtuGate == null ? 185 : await mtuGate!.future;
  }

  Future<void> close() async {
    await characteristic.values.close();
    await connection.close();
  }
}

void main() {
  test(
    'write pacing retains 300 ms gaps without adding an idle wait',
    () async {
      final ble = _Ble();
      final transport = ReactiveScooterTransport(createBle: () => ble);
      addTearDown(ble.close);
      addTearDown(transport.close);
      await transport.connect(
        'scooter',
        profile: BleConnectionProfile(
          layouts: VicontProtocol().connection.layouts,
          writeDelay: const Duration(milliseconds: 300),
        ),
      );
      final first = transport.write([1]);
      await Future<void>.delayed(Duration.zero);
      expect(ble.characteristic.writes, isEmpty);
      await first;
      expect(ble.characteristic.writes.length, 1);
      final second = transport.write([2]);
      await Future<void>.delayed(Duration.zero);
      expect(ble.characteristic.writes.length, 1);
      await second;
      expect(ble.characteristic.writes.length, 2);
      await Future<void>.delayed(const Duration(milliseconds: 310));
      final idle = transport.write([3]);
      await Future<void>.delayed(Duration.zero);
      expect(ble.characteristic.writes.length, 3);
      await idle;
    },
  );
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'cancelling a pending link completes without waiting for timeout',
    () async {
      final ble = _Ble()..autoConnect = false;
      final transport = ReactiveScooterTransport(createBle: () => ble);
      addTearDown(ble.close);
      addTearDown(transport.close);
      final attempt = transport.connect(
        'scooter',
        profile: VicontProtocol().connection,
      );
      final cancelled = expectLater(attempt, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(ble.connection.hasListener, isTrue);
      await transport.disconnect();
      await cancelled.timeout(const Duration(milliseconds: 250));
      expect(ble.connection.hasListener, isFalse);
      expect(ble.events, isEmpty);
    },
  );

  test(
    'immediate cancellation cannot begin a late native connection',
    () async {
      final ble = _Ble();
      final transport = ReactiveScooterTransport(createBle: () => ble);
      addTearDown(ble.close);
      addTearDown(transport.close);
      final attempt = transport.connect(
        'scooter',
        profile: VicontProtocol().connection,
      );
      final cancelled = expectLater(attempt, throwsStateError);
      await transport.disconnect();
      await cancelled;
      expect(ble.connects, 0);
      expect(ble.connection.hasListener, isFalse);
    },
  );

  test(
    'a cancelled attempt cannot clean up its replacement connection',
    () async {
      final ble = _Ble()..autoConnect = false;
      final transport = ReactiveScooterTransport(createBle: () => ble);
      addTearDown(ble.close);
      addTearDown(transport.close);
      final profile = BleConnectionProfile(
        layouts: VicontProtocol().connection.layouts,
      );
      final first = transport.connect('first', profile: profile);
      final cancelled = expectLater(first, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      ble.autoConnect = true;
      await transport.connect('replacement', profile: profile);
      await cancelled;
      expect(ble.connects, 2);
      expect(ble.connection.hasListener, isTrue);
      expect(transport.selection, isNotNull);
      await transport.write(const [1, 2, 3]);
      expect(ble.characteristic.writes, [false]);
    },
  );

  for (final synchronous in [false, true]) {
    test(
      'failed setup cleans its connection; synchronous=$synchronous',
      () async {
        final ble = _Ble()
          ..rejectConnection = synchronous
          ..rejectDiscovery = !synchronous;
        final transport = ReactiveScooterTransport(createBle: () => ble);
        addTearDown(ble.close);
        addTearDown(transport.close);
        await expectLater(
          transport.connect('scooter', profile: VicontProtocol().connection),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'original error',
              synchronous ? 'Native connection failed' : 'Discovery failed',
            ),
          ),
        );
        expect(ble.connection.hasListener, isFalse);
        expect(transport.selection, isNull);
        expect(transport.discoveredServices, isEmpty);
      },
    );
  }

  test('stock client selects FFF0/FFF1 when both services are present', () {
    final selection = selectGattLayout(const [
      GattServiceInfo('fee0', [
        GattCharacteristicInfo('fee2', notify: true, writeWithResponse: true),
      ]),
      GattServiceInfo('fff0', [
        GattCharacteristicInfo(
          'fff1',
          notify: true,
          writeWithoutResponse: true,
        ),
      ]),
    ], VicontProtocol().connection);
    expect(selection?.layoutId, 'fff0-fff1');
    expect(selection?.write, 'fff1');
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'real transport selects stock $platform write mode and MTU policy',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final ble = _Ble();
        final transport = ReactiveScooterTransport(createBle: () => ble);
        addTearDown(ble.close);
        addTearDown(transport.close);
        // No timers in this fixture: exercise actual discovery, MTU and write routing.
        final profile = BleConnectionProfile(
          layouts: VicontProtocol().connection.layouts,
          preferredMtu: 255,
        );
        await transport.connect('scooter', profile: profile);
        await transport.write(const [0xfa, 0xaf, 0xa5, 0x5a, 1, 0, 0x5b]);
        expect(ble.characteristic.writes, [platform == TargetPlatform.iOS]);
        expect(
          ble.events,
          platform == TargetPlatform.android
              ? ['discover', 'mtu:255', 'subscribe', 'write']
              : ['discover', 'subscribe', 'write'],
        );
        expect(
          transport.diagnostics['mtu'],
          platform == TargetPlatform.android ? 185 : null,
        );
      },
    );
  }

  test(
    'disconnect during MTU negotiation never subscribes or writes later',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final ble = _Ble()..mtuGate = Completer<int>();
      final transport = ReactiveScooterTransport(createBle: () => ble);
      addTearDown(ble.close);
      addTearDown(transport.close);
      final attempt = transport.connect(
        'scooter',
        profile: BleConnectionProfile(
          layouts: VicontProtocol().connection.layouts,
          preferredMtu: 255,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await transport.disconnect();
      final result = expectLater(attempt, throwsStateError);
      ble.mtuGate!.complete(185);
      await result;
      expect(ble.events, ['discover', 'mtu:255']);
      expect(transport.selection, isNull);
      expect(transport.diagnostics['mtu'], isNull);
    },
  );

  test('an MTU failure falls back and records the reason', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ble = _Ble()..rejectMtu = true;
    final transport = ReactiveScooterTransport(createBle: () => ble);
    addTearDown(ble.close);
    addTearDown(transport.close);
    await transport.connect(
      'scooter',
      profile: BleConnectionProfile(
        layouts: VicontProtocol().connection.layouts,
        preferredMtu: 255,
      ),
    );
    await transport.write(const [0xfa, 0xaf, 0xa5, 0x5a, 1, 0, 0x5b]);
    expect(ble.events, ['discover', 'mtu:255', 'subscribe', 'write']);
    expect(
      transport.diagnostics['mtuNotice'],
      contains('MTU request rejected'),
    );
  });

  test(
    'disconnect during write delay cannot send on a stale characteristic',
    () async {
      final ble = _Ble();
      final transport = ReactiveScooterTransport(createBle: () => ble);
      addTearDown(ble.close);
      addTearDown(transport.close);
      await transport.connect(
        'scooter',
        profile: BleConnectionProfile(
          layouts: VicontProtocol().connection.layouts,
          writeDelay: const Duration(milliseconds: 20),
        ),
      );
      final write = transport.write(const [0xfa, 0xaf, 0xa5, 0x5a, 1, 0, 0x5b]);
      final result = expectLater(write, throwsStateError);
      await transport.disconnect();
      await result;
      expect(ble.characteristic.writes, isEmpty);
    },
  );

  test('GATT alone never reports a successful scooter connection', () async {
    final transport = FakeTransport()..replyToHandshake = false;
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
      sessionResponseTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(c.dispose);
    final connecting = c.connect(const SavedScooter('id', 'VC_Test'));
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, LinkPhase.connecting);
    expect(c.saved, isNull);
    // An incomplete packet must be logged but must not establish a session.
    transport.received.add(const [0x5a, 0x10, 12, 0x12]);
    await connecting;
    expect(c.ready, isFalse);
    expect(c.phase, LinkPhase.idle);
    expect(c.saved, isNull);
    expect(c.message, contains('did not answer the handshake'));
    expect(transport.writes.length, 2);
    expect(
      c.logs.any((e) => e.direction == 'RX-RAW' && e.message == '5A100C12'),
      isTrue,
    );
    expect(
      c.logs.any((e) => e.direction == 'LINK' && e.fields['write'] == 'fee2'),
      isTrue,
    );
  });

  test(
    'checksum-failed handshake cannot establish or save a connection',
    () async {
      final transport = FakeTransport()..replyToHandshake = false;
      transport.onWrite = (bytes) {
        if (bytes[4] == 1) transport.received.add([0x91, 1, 0, 0]);
      };
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        sessionResponseTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('id', 'VC_Test'));
      expect(c.ready, isFalse);
      expect(c.saved, isNull);
      expect(c.message, contains('did not answer the handshake'));
      expect(
        c.logs.any((e) => e.message.contains('checksum mismatch; ignored')),
        true,
      );
      expect(transport.writes.length, 2);
    },
  );
  test(
    'valid status recovers setup after an abandoned corrupt-length packet',
    () async {
      final transport = FakeTransport()..replyToHandshake = false;
      transport.onWrite = (bytes) {
        if (bytes[4] == 1 && bytes[3] == 0xfa) {
          transport.received.add([0x91, 16, 250, 0]);
          transport.status();
        }
      };
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('id', 'VC_Test'));
      expect(c.ready, isTrue);
      expect(c.saved?.id, 'id');
      expect(c.telemetry.zt, 0x5a);
      expect(c.logs.any((e) => e.message.contains('recovered')), true);
    },
  );

  test(
    'early status completes setup and its binding acknowledgement is retained',
    () async {
      final transport = FakeTransport()..replyToHandshake = false;
      transport.onWrite = (bytes) {
        if (bytes[4] == 1 && bytes[3] == 0xfa) transport.status(second: 0x41);
      };
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.connect(const SavedScooter('id', 'VC_Test'));
      await Future<void>.delayed(Duration.zero);
      expect(c.ready, isTrue);
      expect(transport.writes.where((v) => v[4] == 76).single[6], 2);
      transport.status(second: 0x41);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes.where((v) => v[4] == 76).length, 1);
    },
  );

  test(
    'cancelling the handshake wait immediately permits a new session',
    () async {
      final transport = FakeTransport()..replyToHandshake = false;
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      final attempt = c.connect(const SavedScooter('id', 'VC_Test'));
      await Future<void>.delayed(Duration.zero);
      await c.startDemo();
      await attempt.timeout(const Duration(seconds: 1));
      expect(c.isDemo, isTrue);
      expect(c.ready, isTrue);
      expect(c.saved, isNull);
    },
  );
}
