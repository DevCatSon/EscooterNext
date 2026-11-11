import 'dart:async';

import 'package:escooter_control/services/ble_transport.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

class _Ble extends Fake implements FlutterReactiveBle {
  _Ble(this.states);
  final Stream<BleStatus> states;
  int scans = 0;

  @override
  Future<void> initialize() async {}

  @override
  Stream<BleStatus> get statusStream => states;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) {
    scans++;
    return const Stream.empty();
  }
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'first scan grants permission before starting BLE and awaits ready',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final states = StreamController<BleStatus>();
      addTearDown(states.close);
      final ble = _Ble(states.stream);
      var granted = false;
      var creations = 0;
      var permissionRequests = 0;
      final controller = ScooterController(
        transport: ReactiveScooterTransport(
          createBle: () {
            expect(granted, isTrue);
            creations++;
            return ble;
          },
        ),
        preferences: MemoryPreferenceStore(),
        permissions: () async {
          permissionRequests++;
          granted = true;
        },
      );
      addTearDown(controller.dispose);
      expect(creations, 0);

      final scan = controller.scan();
      states.add(BleStatus.unknown);
      states.add(BleStatus.unauthorized);
      // Deliberately hold the native observer at its stale pre-grant state.
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, LinkPhase.scanning);
      expect(controller.message, isNull);
      expect(ble.scans, 0);

      states.add(BleStatus.ready);
      await scan;
      expect(ble.scans, 1);
      expect(permissionRequests, 1);
      expect(creations, 1);
      expect(controller.message, isNull);
    },
  );

  test('denying Android permission never initializes BLE or scans', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var creations = 0;
    final controller = ScooterController(
      transport: ReactiveScooterTransport(
        createBle: () {
          creations++;
          return _Ble(const Stream.empty());
        },
      ),
      preferences: MemoryPreferenceStore(),
      permissions: () async => throw StateError('Bluetooth access is needed.'),
    );
    addTearDown(controller.dispose);
    await controller.scan();
    expect(controller.phase, LinkPhase.idle);
    expect(controller.message, contains('Bluetooth access is needed'));
    expect(creations, 0);
  });

  test('cancelling while BLE catches up prevents a late scan', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final states = StreamController<BleStatus>();
    addTearDown(states.close);
    final ble = _Ble(states.stream);
    final controller = ScooterController(
      transport: ReactiveScooterTransport(createBle: () => ble),
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(controller.dispose);
    final scan = controller.scan();
    states.add(BleStatus.unauthorized);
    await Future<void>.delayed(Duration.zero);
    await controller.stopScan();
    states.add(BleStatus.ready);
    await scan;
    expect(controller.phase, LinkPhase.idle);
    expect(ble.scans, 0);
  });

  for (final status in [
    BleStatus.poweredOff,
    BleStatus.locationServicesDisabled,
    BleStatus.unsupported,
  ]) {
    test(
      'Android reports $status after a stale authorization update',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final transport = ReactiveScooterTransport(
          createBle: () =>
              _Ble(Stream.fromIterable([BleStatus.unauthorized, status])),
        );
        addTearDown(transport.close);
        final message = switch (status) {
          BleStatus.poweredOff => 'Turn Bluetooth on',
          BleStatus.locationServicesDisabled => 'Location services',
          _ => 'does not support Bluetooth LE',
        };
        await expectLater(
          transport.prepare(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      },
    );
  }

  test(
    'iOS authorization denial is reported without waiting for readiness',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final states = StreamController<BleStatus>();
      addTearDown(states.close);
      final transport = ReactiveScooterTransport(
        createBle: () => _Ble(states.stream),
      );
      addTearDown(transport.close);
      final expectation = expectLater(
        transport.prepare(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Allow Bluetooth'),
          ),
        ),
      );
      states.add(BleStatus.unknown);
      states.add(BleStatus.unauthorized);
      await expectation;
    },
  );

  test(
    'a persistent unauthorized state has a bounded wait and no scan',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final states = StreamController<BleStatus>();
      addTearDown(states.close);
      final ble = _Ble(states.stream);
      final transport = ReactiveScooterTransport(
        createBle: () => ble,
        readinessTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(transport.close);
      final expectation = expectLater(
        transport.prepare(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Allow Bluetooth'),
          ),
        ),
      );
      states.add(BleStatus.unauthorized);
      await expectation;
      expect(ble.scans, 0);
      expect(states.hasListener, isFalse);
    },
  );
}
