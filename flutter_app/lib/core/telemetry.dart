enum Reading {
  voltage,
  current,
  speed,
  battery,
  controllerTemp,
  motorTemp,
  batteryTemp,
  motorSpeed,
  locked,
  bound,
  cruise,
  headlight,
  ambient,
  kickStart,
  gear,
  miles,
  trip,
  odometer,
  instrumentHardware,
  instrumentSoftware,
  controllerHardware,
  controllerSoftware,
  gearMask,
  throttle,
  brake1,
  brake2,
  throttleRaw,
  brake1Raw,
  brake2Raw,
  bmsId,
  bmsFlags,
  bmsVoltage,
  bmsCurrent,
  bmsCycles,
  bmsRated,
  bmsRemaining,
  bmsTemperature,
  workMode,
  maxSpeed,
  startTorque,
  maxTorque,
  brakeStrength,
  rawStartTorque,
  rawMaxTorque,
  rawBrake,
}

/// Last-reported snapshot: absent fields stay null until received, never guessed.
class Telemetry {
  const Telemetry([this.values = const {}, this.zt = 0x5a]);
  final Map<Reading, num> values;
  final int zt;
  num? operator [](Reading reading) => values[reading];
  int? integer(Reading reading) => values[reading]?.toInt();
  bool? flag(Reading reading) =>
      values[reading] == null ? null : values[reading] == 1;
  bool get miles => flag(Reading.miles) == true;
  bool? get locked => flag(Reading.locked);
  int? get gear => switch (integer(Reading.gear)) {
    1 => 1,
    2 => 2,
    3 || 4 || 5 => 3,
    _ => null,
  };
  Set<int>? get availableGears {
    final mask = integer(Reading.gearMask);
    return mask == null
        ? null
        : {
            for (var i = 1; i <= 7; i++)
              if (mask & (1 << (i - 1)) != 0) i,
          };
  }

  Telemetry withValues(Map<Reading, num> changed, {int? sync}) {
    final unchanged = changed.entries.every((e) => values[e.key] == e.value);
    if (unchanged && (sync == null || sync == zt)) return this;
    return Telemetry(
      unchanged ? values : Map.unmodifiable({...values, ...changed}),
      sync ?? zt,
    );
  }

  static final demo = Telemetry(
    Map.unmodifiable({
      Reading.voltage: 48.6,
      Reading.current: 6,
      Reading.speed: 18.4,
      Reading.battery: 82,
      Reading.controllerTemp: 34,
      Reading.motorTemp: 39,
      Reading.batteryTemp: 30,
      Reading.motorSpeed: 612,
      Reading.locked: 0,
      Reading.bound: 1,
      Reading.headlight: 1,
      Reading.cruise: 0,
      Reading.kickStart: 1,
      Reading.gear: 2,
      Reading.gearMask: 7,
      Reading.miles: 0,
      Reading.trip: 4.7,
      Reading.odometer: 1284,
      Reading.instrumentHardware: 3,
      Reading.instrumentSoftware: 18,
      Reading.controllerHardware: 2,
      Reading.controllerSoftware: 27,
      Reading.maxSpeed: 25,
      Reading.startTorque: 5,
      Reading.maxTorque: 7,
      Reading.brakeStrength: 4,
      Reading.throttle: 0,
      Reading.brake1: 0,
      Reading.brake2: 0,
      Reading.throttleRaw: 786,
      Reading.brake1Raw: 0,
      Reading.brake2Raw: 0,
      Reading.bmsId: 1,
      Reading.bmsFlags: 2,
      Reading.bmsVoltage: 48.6,
      Reading.bmsCurrent: 3.2,
      Reading.bmsCycles: 142,
      Reading.bmsRated: 15000,
      Reading.bmsRemaining: 12300,
      Reading.bmsTemperature: 30,
      Reading.workMode: 2,
    }),
  );
}
