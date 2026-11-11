import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/services/ble_transport.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/fake_transport.dart';

class _SlowScanTransport extends FakeTransport {
  final cancellation = Completer<void>();
  late final firstScan = StreamController<NearbyScooter>(
    onCancel: () => cancellation.future,
  );
  final secondScan = StreamController<NearbyScooter>();
  int scans = 0;
  int disconnects = 0;

  @override
  Future<void> disconnect() async {
    disconnects++;
    await super.disconnect();
  }

  @override
  Stream<NearbyScooter> scan() =>
      scans++ == 0 ? firstScan.stream : secondScan.stream;

  @override
  Future<void> close() async {
    if (!cancellation.isCompleted) cancellation.complete();
    await firstScan.close();
    await secondScan.close();
    await super.close();
  }
}

void main() {
  test('delayed demo cleanup cannot replace a newer real connection', () async {
    final transport = _SlowScanTransport();
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await c.scan();
    final demo = c.startDemo();
    await c.connect(const SavedScooter('new', 'VC_New'));
    expect(c.ready, isTrue);
    final disconnects = transport.disconnects;
    transport.cancellation.complete();
    await demo;
    expect(transport.disconnects, disconnects);
    expect(c.isDemo, isFalse);
    expect(c.ready, isTrue);
    expect(c.connectedId, 'new');
  });

  test(
    'a cancelled demo start stays disconnected after scan cleanup',
    () async {
      final transport = _SlowScanTransport();
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
      );
      addTearDown(c.dispose);
      await c.scan();
      final demo = c.startDemo();
      await c.disconnect();
      transport.cancellation.complete();
      await demo;
      expect(c.isDemo, isFalse);
      expect(c.phase, LinkPhase.idle);
    },
  );

  test('an old scan cancellation cannot reset a newer scan', () async {
    final transport = _SlowScanTransport();
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
      scanCooldown: Duration.zero,
    );
    addTearDown(c.dispose);
    await c.scan();
    final oldStop = c.stopScan();
    await c.disconnect();
    await c.scan();
    expect(transport.scans, 2);
    transport.cancellation.complete();
    await oldStop;
    expect(c.phase, LinkPhase.scanning);
    transport.secondScan.add(const NearbyScooter('new', 'VC_New', -40));
    await Future<void>.delayed(Duration.zero);
    expect(c.nearby.single.id, 'new');
    await c.stopScan();
  });

  test('a discovered scooter can connect after stopping its scan', () async {
    final transport = FakeTransport();
    final c = ScooterController(
      transport: transport,
      preferences: MemoryPreferenceStore(),
      permissions: () async {},
    );
    addTearDown(c.dispose);
    await c.scan();
    await c
        .connect(const SavedScooter('test-id', 'VC_Test', protocolId: 'vicont'))
        .timeout(const Duration(seconds: 2));
    expect(c.ready, isTrue);
  });
}
