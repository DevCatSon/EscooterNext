import '../../core/telemetry.dart';
import '../../models/scooter_control.dart';
import '../scooter_protocol.dart';
import 'vicont_codec.dart';
import 'vicont_decoder.dart';

abstract final class VicontCommands {
  static const _codes = {
    ScooterControl.lock: 51,
    ScooterControl.find: 52,
    ScooterControl.kickStart: 53,
    ScooterControl.cruise: 54,
    ScooterControl.seat: 55,
    ScooterControl.helmet: 56,
    ScooterControl.storage: 57,
    ScooterControl.brakeLock: 58,
    ScooterControl.maxSpeed: 60,
    ScooterControl.startTorque: 61,
    ScooterControl.maxTorque: 62,
    ScooterControl.brake: 63,
    ScooterControl.ambient: 65,
    ScooterControl.gear: 66,
    ScooterControl.unit: 67,
    ScooterControl.headlight: 69,
    ScooterControl.workMode: 74,
    ScooterControl.binding: 76,
    ScooterControl.version: 171,
  };
  static const fields = {
    ScooterControl.lock: Reading.locked,
    ScooterControl.headlight: Reading.headlight,
    ScooterControl.cruise: Reading.cruise,
    ScooterControl.kickStart: Reading.kickStart,
    ScooterControl.gear: Reading.gear,
    ScooterControl.unit: Reading.miles,
    ScooterControl.maxSpeed: Reading.maxSpeed,
    ScooterControl.startTorque: Reading.startTorque,
    ScooterControl.maxTorque: Reading.maxTorque,
    ScooterControl.brake: Reading.brakeStrength,
    ScooterControl.workMode: Reading.workMode,
  };
  static ProtocolRequest? request(ScooterCommand command, Telemetry state) {
    final control = command.control;
    final code = control == ScooterControl.raw
        ? command.value
        : _codes[control];
    if (code == null) return null;
    final value = command.value;
    final setting = {
      ScooterControl.maxSpeed,
      ScooterControl.startTorque,
      ScooterControl.maxTorque,
      ScooterControl.brake,
    }.contains(control);
    final toggle = {
      ScooterControl.lock,
      ScooterControl.headlight,
      ScooterControl.cruise,
      ScooterControl.kickStart,
      ScooterControl.unit,
    }.contains(control);
    final List<int> payload;
    if (control == ScooterControl.raw) {
      payload = command.data;
    } else if (command.operation == CommandOperation.read) {
      if (!setting &&
          control != ScooterControl.workMode &&
          control != ScooterControl.version) {
        return null;
      }
      payload = [control == ScooterControl.version ? 173 : Protocol.query];
    } else if (command.operation == CommandOperation.reset) {
      if (!setting) return null;
      payload = [Protocol.reset];
    } else {
      if (value == null) return null;
      if (toggle && (value < 0 || value > 1)) return null;
      if ((control == ScooterControl.gear ||
              control == ScooterControl.workMode) &&
          (value < 1 || value > 3)) {
        return null;
      }
      if (control == ScooterControl.ambient &&
          (value < 1 ||
              value > 5 ||
              command.data.length != 1 ||
              command.data.single < 0 ||
              command.data.single > 255)) {
        return null;
      }
      payload = switch (control) {
        ScooterControl.lock ||
        ScooterControl.headlight ||
        ScooterControl.cruise ||
        ScooterControl.kickStart => [value == 1 ? 2 : 1],
        ScooterControl.unit => [value == 1 ? 2 : 1],
        ScooterControl.maxSpeed => [Protocol.speedByte(value)],
        ScooterControl.startTorque ||
        ScooterControl.maxTorque => [Protocol.torqueByte(value)],
        ScooterControl.brake => [Protocol.brakeByte(value)],
        ScooterControl.ambient => [value, value == 5 ? command.data.single : 0],
        _ => [value],
      };
    }
    // Validate before queueing; encode again at dispatch with the latest sync byte.
    Protocol.command(state.zt, code, payload);
    return ProtocolRequest(
      control: control,
      encode: (latest) => Protocol.command(latest.zt, code, payload),
      readOnly: command.operation == CommandOperation.read,
      allowedWhileLocked:
          control == ScooterControl.lock || control == ScooterControl.find,
      changesSettings: setting,
      accepts: (event) {
        final frame = event.token;
        if (frame is! IncomingFrame || !frame.checksumOk) return false;
        if (control == ScooterControl.version) {
          return frame.code == 171 || frame.code == 18;
        }
        if (toggle || control == ScooterControl.gear) {
          return frame.code == 17 &&
              frame.data.isNotEmpty &&
              (control == ScooterControl.gear
                      ? event.telemetry.gear
                      : event.telemetry[fields[control]!]) ==
                  value;
        }
        if (control == ScooterControl.workMode) {
          return frame.code == 74 &&
              event.telemetry[Reading.workMode] != null &&
              (command.operation == CommandOperation.read ||
                  event.telemetry[Reading.workMode] == value);
        }
        return frame.code == code && (setting ? frame.data.isNotEmpty : true);
      },
    );
  }

  static Telemetry simulate(ScooterCommand command, Telemetry state) {
    final control = command.control, field = fields[command.control];
    if (command.operation == CommandOperation.read) return state;
    if (command.operation == CommandOperation.reset) {
      final defaults = {
        ScooterControl.maxSpeed: 25,
        ScooterControl.startTorque: 5,
        ScooterControl.maxTorque: 7,
        ScooterControl.brake: 4,
      };
      return field == null
          ? state
          : state.withValues({field: defaults[control]!});
    }
    final request = VicontCommands.request(command, state);
    if (request == null) return state;
    if ({
      ScooterControl.maxSpeed,
      ScooterControl.startTorque,
      ScooterControl.maxTorque,
      ScooterControl.brake,
    }.contains(control)) {
      final bytes = request.encode(state);
      return state.apply(
        IncomingFrame(state.zt, _codes[control]!, [bytes[6], 200], true),
      );
    }
    if (control == ScooterControl.ambient) {
      return state.withValues({Reading.ambient: command.value == 1 ? 0 : 1});
    }
    return field == null ? state : state.withValues({field: command.value!});
  }
}
