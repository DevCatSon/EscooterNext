import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/services/phone_speed.dart';
import 'package:escooter_control/services/preferences.dart';
import 'package:escooter_control/services/scooter_controller.dart';

import 'support/fake_transport.dart';

class FakePhoneSpeed implements PhoneSpeedProvider {
  final values = StreamController<PhoneSpeedSample>.broadcast(sync: true);
  int authorizations = 0;
  bool deny = false;
  @override
  Future<void> authorize() async {
    authorizations++;
    if (deny) {
      throw PlatformException(
        code: 'location_permission',
        message: 'Allow Precise Location.',
      );
    }
  }

  @override
  Stream<PhoneSpeedSample> get samples => values.stream;
  void emit({
    double speed = 5,
    double horizontal = 5,
    double? accuracy = .5,
    Duration age = Duration.zero,
  }) => values.add(
    PhoneSpeedSample(
      metersPerSecond: speed,
      horizontalAccuracy: horizontal,
      speedAccuracy: accuracy,
      age: age,
      receivedAt: DateTime.now(),
    ),
  );
}

PhoneSpeedSample sample(
  DateTime now, {
  double speed = 5,
  double horizontal = 5,
  double? accuracy = .5,
  Duration age = Duration.zero,
}) => PhoneSpeedSample(
  metersPerSecond: speed,
  horizontalAccuracy: horizontal,
  speedAccuracy: accuracy,
  age: age,
  receivedAt: now,
);

void main() {
  test('phone samples use m/s, preserve a valid zero and reject bad quality or time', () {
    final now = DateTime.utc(2026, 10, 24);
    expect(sample(now).kmh, 18);
    expect(sample(now, speed: 0).usable(now), true);
    for (final invalid in [
      sample(now, speed: -1),
      sample(now, speed: double.nan),
      sample(now, horizontal: 50),
      sample(now, accuracy: 3),
      sample(now, accuracy: -1),
      sample(now, age: const Duration(seconds: 4)),
      sample(now, age: const Duration(seconds: -1)),
      sample(now.add(const Duration(seconds: 1))),
    ]) {
      expect(invalid.usable(now), false);
    }
    expect(sample(now, horizontal: 10, accuracy: null).usable(now), true);
    expect(sample(now, horizontal: 20, accuracy: null).usable(now), false);
  });
  test('mixed combines agreeing readings, favors a precise fix and detects disagreement', () {
    final now = DateTime.now();
    final ordinary = estimateSpeed(SpeedSource.mixed, 20, sample(now));
    expect(ordinary.kmh, closeTo(19.5, .001));
    expect(ordinary.origin, 'Phone + scooter');
    final precise = estimateSpeed(
      SpeedSource.mixed,
      20,
      sample(now, accuracy: .1),
    );
    expect(precise.kmh!, lessThan(ordinary.kmh!));
    final disagreement = estimateSpeed(
      SpeedSource.mixed,
      45,
      sample(now, speed: 0),
    );
    expect(disagreement.kmh, 0);
    expect(disagreement.origin, contains('disagree'));
    expect(estimateSpeed(SpeedSource.mixed, 20, null).kmh, 20);
    expect(estimateSpeed(SpeedSource.mixed, null, sample(now)).kmh, 18);
    expect(estimateSpeed(SpeedSource.mixed, null, null).kmh, isNull);
    expect(estimateSpeed(SpeedSource.phone, 20, null).kmh, isNull);
  });
  test(
    'a stale phone reading expires and cannot survive pause or a source switch',
    () async {
      final provider = FakePhoneSpeed();
      final monitor = PhoneSpeedMonitor(provider);
      monitor.setEnabled(true);
      provider.emit(age: const Duration(milliseconds: 2800));
      expect(monitor.sample, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 240));
      expect(monitor.sample, isNull);
      expect(monitor.status, contains('stale'));
      provider.emit();
      expect(monitor.sample, isNotNull);
      monitor.setEnabled(false);
      expect(provider.values.hasListener, false);
      expect(monitor.sample, isNull);
      monitor.dispose();
      await provider.values.close();
    },
  );
  test('phone and mixed affect display only, and location runs only during an active real link', () async {
    final provider = FakePhoneSpeed(), transport = FakeTransport();
    final prefs = MemoryPreferenceStore();
    final c = ScooterController(
      transport: transport,
      preferences: prefs,
      permissions: () async {},
      phoneSpeedProvider: provider,
    );
    await c.connect(const SavedScooter('id', 'VC_Test'));
    transport.emit(16, [0x12, 0xfc, 0, 0, 0, 200, 80]);
    expect(c.displaySpeedEstimate.kmh, 20);
    expect(provider.authorizations, 0);
    expect(provider.values.hasListener, false);
    await c.setSpeedSource(SpeedSource.phone);
    expect(provider.authorizations, 1);
    expect(c.displaySpeedEstimate.kmh, isNull);
    provider.emit();
    expect(c.displaySpeedEstimate.kmh, 18);
    expect(c.telemetry[Reading.speed], 20);
    final writes = transport.writes.length;
    await c.setSpeedSource(SpeedSource.mixed);
    expect(c.displaySpeedEstimate.kmh, inExclusiveRange(18, 20));
    expect(transport.writes.length, writes);
    c.setAppActive(false);
    expect(provider.values.hasListener, false);
    expect(c.phoneSpeed.sample, isNull);
    c.setAppActive(true);
    expect(provider.values.hasListener, true);
    expect(c.phoneSpeed.sample, isNull);
    await c.setSpeedSource(SpeedSource.scooter);
    expect(provider.values.hasListener, false);
    expect(prefs.read('speedSource'), 'scooter');
    c.dispose();
    await provider.values.close();
  });
  test(
    'permission denial preserves the selected mode and leaves BLE working',
    () async {
      final provider = FakePhoneSpeed()..deny = true;
      final c = ScooterController(
        transport: FakeTransport(),
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        phoneSpeedProvider: provider,
      );
      await c.connect(const SavedScooter('id', 'VC_Test'));
      await c.setSpeedSource(SpeedSource.phone);
      expect(c.speedSource, SpeedSource.scooter);
      expect(c.ready, true);
      expect(c.message, 'Phone speed: Allow Precise Location.');
      expect(provider.values.hasListener, false);
      c.dispose();
      await provider.values.close();
    },
  );
  test('restored preferences never prompt by themselves and Demo never starts location', () async {
    final provider = FakePhoneSpeed();
    final prefs = MemoryPreferenceStore();
    await prefs.write('speedSource', 'mixed');
    final c = ScooterController(
      transport: FakeTransport(),
      preferences: prefs,
      permissions: () async {},
      phoneSpeedProvider: provider,
    );
    expect(provider.authorizations, 0);
    expect(provider.values.hasListener, false);
    await c.startDemo();
    expect(provider.values.hasListener, false);
    expect(c.displaySpeedEstimate.origin, 'Demo');
    await c.connect(const SavedScooter('id', 'VC_Test'));
    expect(provider.authorizations, 0);
    expect(provider.values.hasListener, true);
    await c.disconnect();
    expect(provider.values.hasListener, false);
    c.dispose();
    await provider.values.close();
  });
  test(
    'mixed never falls back to stale scooter speed when GPS is unavailable',
    () async {
      final provider = FakePhoneSpeed(), transport = FakeTransport();
      final c = ScooterController(
        transport: transport,
        preferences: MemoryPreferenceStore(),
        permissions: () async {},
        phoneSpeedProvider: provider,
      );
      await c.connect(const SavedScooter('id', 'VC_Test'));
      transport.emit(16, [0x12, 0xfc, 0, 0, 0, 200, 80]);
      await c.setSpeedSource(SpeedSource.mixed);
      expect(c.displaySpeedEstimate.kmh, 20);
      await Future<void>.delayed(const Duration(milliseconds: 3050));
      expect(c.displaySpeedEstimate.kmh, isNull);
      expect(c.telemetry[Reading.speed], 20);
      c.dispose();
      await provider.values.close();
    },
  );
}
