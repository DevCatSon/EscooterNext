enum Feature {
  headlight,
  cruise,
  kickStart,
  ambient,
  seat,
  helmet,
  storage,
  brakeLock,
}

enum ScooterControl {
  lock('Lock'),
  find('Find scooter'),
  headlight('Headlight'),
  cruise('Cruise control'),
  kickStart('Kick start'),
  gear('Ride mode'),
  unit('Speed unit'),
  maxSpeed('Speed limit'),
  startTorque('Starting torque'),
  maxTorque('Driving torque'),
  brake('Brake strength'),
  ambient('Ambient lighting'),
  seat('Seat / cabin'),
  helmet('Helmet box'),
  storage('Storage basket'),
  brakeLock('Brake lock'),
  workMode('Work mode'),
  version('Versions'),
  binding('Binding acknowledgement'),
  raw('Raw command');

  const ScooterControl(this.label);
  final String label;
}

extension FeatureControl on Feature {
  ScooterControl get control => ScooterControl.values.byName(name);
}

enum CommandOperation { set, read, reset }

class ScooterCommand {
  const ScooterCommand(
    this.control, {
    this.value,
    this.data = const [],
    this.operation = CommandOperation.set,
  });
  final ScooterControl control;
  final int? value;
  final List<int> data;
  final CommandOperation operation;
}

class ControlRange {
  const ControlRange(this.min, this.max);
  final int min, max;
  int clamp(int value) => value.clamp(min, max);
}
