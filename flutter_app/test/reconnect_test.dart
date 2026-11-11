import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

const saved = SavedScooter('saved-id', 'VC_Saved', protocolId: 'vicont');
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 15));
Future<void> waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Connection state did not settle.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  late FakeTransport transport;
  late MemoryPreferenceStore prefs;
  late ScooterController c;
  setUp(() {
    transport = FakeTransport();
    prefs = MemoryPreferenceStore()..values['scooter'] = saved.encode();
    c = ScooterController(
      transport: transport,
      preferences: prefs,
      permissions: () async {},
      reconnectDelays: const [
        Duration(milliseconds: 3),
        Duration(milliseconds: 3),
      ],
      sessionResponseTimeout: const Duration(milliseconds: 3),
    );
  });
  tearDown(() => c.dispose());

  test(
    'an existing saved scooter skips first-time setup and reconnects once',
    () async {
      expect(c.hasSeenSetup, isTrue);
      c.startConnectionLifecycle();
      c.startConnectionLifecycle();
      await settle();
      expect(c.ready, isTrue);
      expect(c.reconnecting, isFalse);
      expect(transport.connections, 1);
      expect(transport.prepares, 1);
      expect(c.setupComplete, isTrue);
      expect(prefs.read('setupComplete'), 'true');
      expect(c.connectedId, saved.id);
    },
  );

  test(
    'a lost link reconnects to the saved scooter without opening setup',
    () async {
      c.startConnectionLifecycle();
      await settle();
      transport.links.add(null);
      await settle();
      expect(c.ready, isTrue);
      expect(transport.connections, 2);
      expect(c.logs.any((e) => e.fields['event'] == 'auto_reconnect'), isTrue);
    },
  );

  test('manual disconnect stays disconnected across resume', () async {
    c.startConnectionLifecycle();
    await settle();
    await c.disconnect();
    c.setAppActive(false);
    c.setAppActive(true);
    await settle();
    expect(c.ready, isFalse);
    expect(c.reconnecting, isFalse);
    expect(transport.connections, 1);
  });

  test('background loss waits until foreground before reconnecting', () async {
    c.startConnectionLifecycle();
    await settle();
    c.setAppActive(false);
    transport.links.add(null);
    await settle();
    expect(c.ready, isFalse);
    expect(transport.connections, 1);
    c.setAppActive(true);
    await settle();
    expect(c.ready, isTrue);
    expect(transport.connections, 2);
  });

  test(
    'turning off auto reconnect persists and prevents a dropped-link retry',
    () async {
      c.startConnectionLifecycle();
      await settle();
      await c.setAutoReconnect(false);
      expect(prefs.read('autoReconnect'), 'false');
      transport.links.add(null);
      await settle();
      expect(c.ready, isFalse);
      expect(transport.connections, 1);
      await c.setAutoReconnect(true);
      await settle();
      expect(c.ready, isTrue);
      expect(transport.connections, 2);
    },
  );

  test(
    'silent peripherals have a bounded retry budget and are never marked ready',
    () async {
      transport.replyToHandshake = false;
      c.startConnectionLifecycle();
      await waitUntil(() => transport.connections == 3 && !c.reconnecting);
      expect(transport.connections, 3);
      expect(c.reconnecting, isFalse);
      expect(c.ready, isFalse);
      expect(c.message, contains('did not answer'));
    },
  );

  test(
    'demo and exiting demo never reconnect to a remembered physical scooter',
    () async {
      await c.startDemo();
      c.startConnectionLifecycle();
      await settle();
      expect(transport.connections, 0);
      await c.disconnect();
      c.setAppActive(true);
      await settle();
      expect(transport.connections, 0);
      expect(c.saved?.id, saved.id);
    },
  );

  test('forgetting the saved scooter cancels pending retries', () async {
    transport.replyToHandshake = false;
    c.startConnectionLifecycle();
    await settle();
    await c.forget();
    final count = transport.connections;
    await settle();
    expect(c.saved, isNull);
    expect(prefs.read('scooter'), isNull);
    expect(c.reconnecting, isFalse);
    expect(transport.connections, count);
  });
}
