import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:escooter_control/core/protocol.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/integrations/vicont/vicont_protocol.dart';

import 'support/fake_transport.dart';

IncomingFrame frame(int code, List<int> data) =>
    NotificationFramer().add(incoming(code, data)).single;

void main() {
  test('G30 captured notifications decode without false recovery messages', () {
    final capture = jsonDecode(
      File('test/fixtures/gyrocopters_g30_notifications.json')
          .readAsStringSync(),
    ) as Map;
    final notifications = (capture['notifications'] as List)
        .map((hex) => Protocol.fromHex(hex as String))
        .toList();
    final parser = NotificationFramer();
    for (var round = 0; round < 3; round++) {
      final codes = <int>[];
      for (final notification in notifications) {
        final frames = parser.add(notification);
        expect(parser.discardedBytes, 0);
        expect(frames.single.checksumOk, isTrue);
        codes.add(frames.single.code);
      }
      expect(codes, [18, 19, 20, 16, 17]);
    }
    final session = VicontProtocol().createSession();
    var state = const Telemetry();
    for (final bytes in [...notifications, ...notifications]) {
      for (final event in session.decode(bytes, state)) {
        expect(event.diagnosticOnly, isFalse);
        state = event.telemetry;
      }
    }
    expect(state[Reading.voltage], closeTo(41.66, .001));
    expect(state[Reading.battery], 100);
    expect(state[Reading.controllerTemp], 21);
    expect(state[Reading.odometer], 900);
    expect(state.zt, 0x5a);
  });
  test('optional zero trailers work inside a coalesced notification', () {
    final parser = NotificationFramer();
    final frames = parser.add([
      ...incoming(60, [25]),
      0,
      ...incoming(61, [100]),
      0,
    ]);
    expect(frames.map((f) => f.code), [60, 61]);
    expect(parser.discardedBytes, 0);
    expect(parser.add(incoming(62, [120])).single.code, 62);
    expect(parser.discardedBytes, 0);
  });
  test('zero sync bytes and split packets are not mistaken for trailers', () {
    final parser = NotificationFramer();
    parser.add(incoming(60, [25]));
    final packet = incoming(17, [3, 1, 0, 0, 0, 0], zt: 0);
    expect(parser.add(packet.take(1).toList()), isEmpty);
    final frame = parser.add(packet.skip(1).toList()).single;
    expect(frame.zt, 0);
    expect(frame.code, 17);
    expect(frame.checksumOk, true);
  });
  test('a large notification batch preserves every frame and a split tail', () {
    final parser = NotificationFramer();
    final packet = incoming(16, [0x12, 0xfc, 0, 0, 0, 10, 80]);
    final batch = [for (var i = 0; i < 1000; i++) ...packet, ...packet.take(3)];
    final frames = parser.add(batch);
    expect(frames.length, 1000);
    expect(frames.every((f) => f.checksumOk), isTrue);
    expect(parser.add(packet.skip(3).toList()).single.code, 16);
  });
  test(
    'handshake literals and lock frames match the original-client vectors',
    () {
      expect(Protocol.handshake.map(Protocol.hex), [
        'FAAFA55A01005B',
        'FAAFA5FA01005B',
      ]);
      expect(Protocol.hex(Protocol.command(0x5a, 51, [1])), 'FAAFA55A3301018F');
      expect(Protocol.hex(Protocol.command(0x5a, 51, [2])), 'FAAFA55A33010290');
    },
  );
  test('switch polarity matches the source and the 31 km/h command has correct checksum', () {
    expect(Protocol.switchByte(true), 1);
    expect(Protocol.switchByte(false), 2);
    expect(
      Protocol.hex(Protocol.command(0x5a, 53, [Protocol.switchByte(true)])),
      'FAAFA55A35010191',
    );
    expect(Protocol.hex(Protocol.command(0x5a, 69, [2])), 'FAAFA55A450102A2');
    expect(Protocol.hex(Protocol.command(0x5a, 60, [31])), 'FAAFA55A3C011FB6');
    expect(
      Protocol.hex(Protocol.command(0x5a, 60, [Protocol.query])),
      'FAAFA55A3C010097',
    );
  });
  test('speed selection never emits query or restore sentinels as a limit', () {
    for (final value in [-100, 0, 1, 25, 50, 255, 1000]) {
      expect(Protocol.speedByte(value), inInclusiveRange(1, 31));
    }
    expect(Protocol.speedByte(50), 31);
  });
  test(
    'framer handles joined frames, bytewise fragments and incomplete tails',
    () {
      final first = incoming(17, [0x23, 1]);
      final second = incoming(60, [50]);
      final framer = NotificationFramer();
      final decoded = <IncomingFrame>[];
      for (final byte in [...first, ...second]) {
        decoded.addAll(framer.add([byte]));
      }
      expect(decoded.map((e) => e.code), [17, 60]);
      expect(decoded.every((e) => e.checksumOk), true);
      expect(framer.add([0x5a, 17]), isEmpty);
      framer.clear();
      expect(framer.add(second).single.code, 60);
    },
  );
  test(
    'checksum mismatches are flagged rather than silently recast as valid',
    () {
      final bytes = incoming(60, [25])..last = 0;
      expect(NotificationFramer().add(bytes).single.checksumOk, false);
    },
  );
  test('a fresh notification recovers after an abandoned partial packet', () {
    final parser = NotificationFramer();
    expect(parser.add([0xa1, 16, 250, 99]), isEmpty);
    final frames = parser.add(incoming(17, [3, 1, 0, 100, 0, 20]));
    expect(frames.map((frame) => frame.code), [17]);
    expect(frames.single.checksumOk, isTrue);
    expect(frames.single.zt, 0x5a);
  });
  test('garbage and a corrupt length cannot swallow later valid packets', () {
    final parser = NotificationFramer();
    final frames = parser.add([
      0,
      0,
      240,
      99,
      ...incoming(16, [0x12, 0xfc, 0, 0, 0, 10, 80]),
      ...incoming(60, [25]),
    ]);
    expect(
      frames.where((frame) => frame.checksumOk).map((frame) => frame.code),
      [16, 60],
    );
  });
  test('a valid split packet wins over a frame-like continuation', () {
    final parser = NotificationFramer();
    final continuation = incoming(60, [25]);
    final packet = incoming(19, [0, 1, ...continuation]);
    final cut = packet.length - continuation.length - 1;
    expect(parser.add(packet.take(cut).toList()), isEmpty);
    final frames = parser.add(packet.skip(cut).toList());
    expect(frames.length, 1);
    expect(frames.single.code, 19);
    expect(frames.single.data, [0, 1, ...continuation]);
  });
  test('repeated leading garbage never shifts the next notification', () {
    final parser = NotificationFramer();
    // Literal status vector, independent of the test frame builder.
    const status = [0x5a, 0x11, 6, 3, 1, 0, 100, 0, 20, 0xed];
    for (var i = 0; i < 100; i++) {
      final frames = parser.add([0xff, ...status]);
      expect(frames.length, 1);
      expect(frames.single.code, 17);
      expect(frames.single.checksumOk, isTrue);
    }
  });
  test(
    'incomplete known packets retain frame-like bytes inside the payload',
    () {
      final parser = NotificationFramer();
      final payload = [
        ...incoming(60, [25]),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ];
      final packet = incoming(19, payload);
      expect(parser.add(packet.take(9).toList()), isEmpty);
      final frames = parser.add(packet.skip(9).toList());
      expect(frames.length, 1);
      expect(frames.single.code, 19);
      expect(frames.single.data, payload);
      expect(frames.single.checksumOk, isTrue);
    },
  );
  test('bad hex and oversized raw payloads are rejected', () {
    expect(() => Protocol.fromHex('ABC'), throwsFormatException);
    expect(() => Protocol.fromHex('GG'), throwsFormatException);
    expect(Protocol.fromHex('00 AD 01'), [0, 173, 1]);
    expect(() => Protocol.command(90, 256, []), throwsArgumentError);
    expect(() => Protocol.command(90, 51, [-1]), throwsArgumentError);
    expect(
      () => Protocol.command(90, 51, List.filled(256, 0)),
      throwsArgumentError,
    );
  });
  test(
    'motor frame preserves all reported temperatures including a valid zero',
    () {
      final state = const Telemetry().apply(
        frame(16, [0x12, 0xfc, 0, 6, 0, 184, 82, 34, 39, 0, 2, 100]),
      );
      expect(state[Reading.voltage], closeTo(48.6, .0001));
      expect(state[Reading.speed], closeTo(18.4, .0001));
      expect(state[Reading.current], 6);
      expect(state[Reading.battery], 82);
      expect(state[Reading.controllerTemp], 34);
      expect(state[Reading.motorTemp], 39);
      expect(state[Reading.batteryTemp], 0);
      expect(state[Reading.motorSpeed], 612);
    },
  );
  test(
    'short frames retain old fields while never-received fields stay unknown',
    () {
      final old = const Telemetry().withValues({
        Reading.motorTemp: 39,
        Reading.speed: 18.4,
        Reading.trip: 4.7,
        Reading.odometer: 1284,
      });
      final motor = old.apply(frame(16, [0x12, 0xfc]));
      expect(motor[Reading.motorTemp], 39);
      expect(motor[Reading.speed], 18.4);
      expect(motor[Reading.batteryTemp], isNull);
      final status = motor.apply(frame(17, [0x23, 1]));
      expect(status[Reading.trip], 4.7);
      expect(status[Reading.odometer], 1284);
      expect(status.flag(Reading.kickStart), true);
      expect(const Telemetry().apply(frame(16, [])).values, isEmpty);
    },
  );
  test(
    'real status capture decodes gear, headlight, unit and trip offsets',
    () {
      final state = const Telemetry().apply(
        frame(17, [0x8b, 0x42, 0, 100, 2, 0xf1, 5, 3, 0, 0]),
      );
      expect(state.gear, 3);
      expect(state.miles, true);
      expect(state.flag(Reading.headlight), true);
      expect(state.locked, true);
      expect(state.flag(Reading.bound), true);
      expect(state[Reading.trip], 1);
      expect(state[Reading.odometer], 753);
    },
  );
  test('real version capture and gear-availability mask match the original implementation', () {
    final state = const Telemetry().apply(
      frame(18, [0x9e, 0xcd, 0x68, 0x25, 0, 0, 0x0a, 0x2c, 7]),
    );
    expect(state[Reading.instrumentHardware], 104);
    expect(state[Reading.instrumentSoftware], 37);
    expect(state[Reading.controllerHardware], 10);
    expect(state[Reading.controllerSoftware], 44);
    expect(state.availableGears, {1, 2, 3});
    expect(const Telemetry().availableGears, isNull);
    expect(Protocol.displayGear(4), 3);
    expect(Protocol.displayGear(5), 3);
    expect(Protocol.displayGear(0), isNull);
  });
  test('sensor capture and BMS overlap retain the original offsets', () {
    final sensor = const Telemetry().apply(
      frame(19, [0, 0, 0, 0, 0, 0, 3, 0x12, 0, 0, 0, 0]),
    );
    expect(sensor[Reading.throttle], 0);
    expect(sensor[Reading.throttleRaw], 786);
    expect(sensor[Reading.brake2Raw], 0);
    final bms = const Telemetry().apply(
      frame(31, [0, 5, 0x14, 0xdc, 0, 100, 0, 12, 0x0b, 0xb8, 5, 0x78, 0, 25]),
    );
    expect(bms[Reading.bmsId], 5);
    expect(bms[Reading.bmsFlags], 5);
    expect(bms[Reading.bmsVoltage], closeTo(53.4, .0001));
    expect(bms[Reading.bmsCurrent], 1);
    expect(bms[Reading.bmsCycles], 12);
    expect(bms[Reading.bmsRated], 3000);
    expect(bms[Reading.bmsRemaining], 1400);
    expect(bms[Reading.bmsTemperature], 25);
    expect(const Telemetry().apply(frame(31, [0, 5]))[Reading.bmsId], isNull);
  });
  test('torque and brake round trips cover every available UI level', () {
    for (var level = 1; level <= 10; level++) {
      final byte = Protocol.torqueByte(level);
      expect(
        const Telemetry().apply(frame(61, [byte, 200]))[Reading.startTorque],
        level,
      );
      expect(
        const Telemetry().apply(frame(62, [byte, 200]))[Reading.maxTorque],
        level,
      );
    }
    for (var level = 0; level <= 9; level++) {
      expect(
        const Telemetry().apply(
          frame(63, [Protocol.brakeByte(level), 200]),
        )[Reading.brakeStrength],
        level,
      );
    }
    expect(Protocol.brakeByte(0), 1);
    expect(Protocol.torqueByte(100), 200);
  });
  test(
    'one-byte and zero-scale configuration responses use the source defaults',
    () {
      expect(const Telemetry().apply(frame(61, [50]))[Reading.startTorque], 5);
      expect(
        const Telemetry().apply(frame(61, [50, 0]))[Reading.startTorque],
        5,
      );
      expect(const Telemetry().apply(frame(62, [10]))[Reading.maxTorque], 4);
      expect(const Telemetry().apply(frame(60, [60]))[Reading.maxSpeed], 60);
    },
  );
  test('work-mode query echoes do not manufacture a mode', () {
    expect(const Telemetry().apply(frame(74, [0]))[Reading.workMode], isNull);
    expect(const Telemetry().apply(frame(74, [2, 0]))[Reading.workMode], 2);
    expect(const Telemetry().apply(frame(74, [9]))[Reading.workMode], isNull);
  });
  test(
    'miles conversion uses the same factor without modifying wire units',
    () {
      expect(Protocol.displayDistance(50, true), closeTo(31.06856, .0001));
      expect(Protocol.displayDistance(50, false), 50);
    },
  );
}
