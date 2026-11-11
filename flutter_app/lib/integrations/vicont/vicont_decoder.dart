import '../../core/telemetry.dart';
import 'vicont_codec.dart';

extension VicontTelemetryDecoder on Telemetry {
  Telemetry apply(IncomingFrame frame) {
    final data = frame.data;
    int? byte(int offset) => offset < data.length ? data[offset] : null;
    int? word(int offset) => offset + 1 < data.length
        ? (data[offset] << 8) | data[offset + 1]
        : null;
    final changed = <Reading, num>{};
    void set(Reading key, num? value) {
      if (value != null) changed[key] = value;
    }

    void bits(int? value, Map<Reading, int> offsets) {
      if (value == null) return;
      for (final entry in offsets.entries) {
        changed[entry.key] = (value >> entry.value) & 1;
      }
    }

    switch (frame.code) {
      case 16:
        set(Reading.voltage, word(0) == null ? null : word(0)! * .01);
        set(Reading.current, word(2));
        set(Reading.speed, word(4) == null ? null : word(4)! * .1);
        set(Reading.battery, byte(6));
        set(Reading.controllerTemp, byte(7));
        set(Reading.motorTemp, byte(8));
        set(Reading.batteryTemp, byte(9));
        set(Reading.motorSpeed, word(10));
      case 17:
        final flags = byte(0);
        if (flags != null) {
          set(Reading.gear, flags & 7);
        }
        bits(flags, {
          Reading.headlight: 3,
          Reading.kickStart: 5,
          Reading.cruise: 6,
          Reading.miles: 7,
        });
        bits(byte(1), {
          Reading.locked: 1,
          Reading.ambient: 5,
          Reading.bound: 6,
        });
        set(Reading.trip, word(2) == null ? null : word(2)! / 100);
        set(Reading.odometer, word(4));
      case 18:
        set(Reading.instrumentHardware, byte(2));
        set(Reading.instrumentSoftware, byte(3));
        set(Reading.controllerHardware, byte(6));
        set(Reading.controllerSoftware, byte(7));
        set(Reading.gearMask, byte(8));
      case 19:
        const sensors = [
          Reading.throttle,
          Reading.brake1,
          Reading.brake2,
          Reading.throttleRaw,
          Reading.brake1Raw,
          Reading.brake2Raw,
        ];
        for (var i = 0; i < sensors.length; i++) {
          set(sensors[i], word(i * 2));
        }
      case 31:
        // The flags overlap the low byte of the id in the original decoder.
        if (data.length >= 6) {
          set(Reading.bmsId, word(0));
          set(Reading.bmsFlags, byte(1));
          set(Reading.bmsVoltage, word(2)! * .01);
          set(Reading.bmsCurrent, word(4)! * .01);
          set(Reading.bmsCycles, word(6));
          set(Reading.bmsRated, word(8));
          set(Reading.bmsRemaining, word(10));
          set(Reading.bmsTemperature, word(12));
        }
      case Protocol.maxSpeed:
        set(Reading.maxSpeed, byte(0));
      case Protocol.startTorque:
        if (byte(0) != null) {
          set(Reading.rawStartTorque, byte(0));
          set(
            Reading.startTorque,
            Protocol.torqueLevel(
              byte(0)!,
              data.length == 2 ? byte(1) : null,
              starting: true,
            ),
          );
        }
      case Protocol.maxTorque:
        if (byte(0) != null) {
          set(Reading.rawMaxTorque, byte(0));
          set(
            Reading.maxTorque,
            Protocol.torqueLevel(byte(0)!, data.length == 2 ? byte(1) : null),
          );
        }
      case Protocol.brake:
        if (byte(0) != null) {
          set(Reading.rawBrake, byte(0));
          set(
            Reading.brakeStrength,
            Protocol.brakeLevel(byte(0)!, data.length == 2 ? byte(1) : null),
          );
        }
      case Protocol.version:
        set(Reading.instrumentHardware, byte(0));
        set(Reading.instrumentSoftware, byte(1));
      case Protocol.workMode:
        final value = byte(data.length >= 2 ? data.length - 2 : 0);
        if (value != null && value >= 1 && value <= 3) {
          set(Reading.workMode, value);
        }
    }
    return withValues(changed, sync: frame.zt);
  }
}
