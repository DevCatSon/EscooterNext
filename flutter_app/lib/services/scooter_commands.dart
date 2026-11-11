part of 'scooter_controller.dart';

extension ScooterCommands on ScooterController {
  Future<bool> _confirmed(ScooterCommand command) async {
    final control = command.control;
    if (!ready || pending(control) || !supportsControl(control)) return false;
    final request = _session!.request(command, telemetry);
    if (request == null) {
      _message('${control.label} is unavailable for this integration.');
      return false;
    }
    if (telemetry.locked == true &&
        !request.readOnly &&
        !request.allowedWhileLocked) {
      _message('Unlock the scooter to change its controls.');
      return false;
    }
    if (isDemo) {
      telemetry = _session!.simulate(command, telemetry);
      if (request.changesSettings) configRevision++;
      _log('DEMO', '${control.label} (simulated)');
      _changed();
      return true;
    }
    final epoch = _epoch, pendingRequest = _Pending(request.accepts);
    _pending[control] = pendingRequest;
    _changed();
    try {
      await _queueWrite(() {
        // A report can lock the scooter while another command is being written.
        if (telemetry.locked == true &&
            !request.readOnly &&
            !request.allowedWhileLocked) {
          throw StateError('Unlock the scooter to change its controls.');
        }
        return request.encode(telemetry);
      }, epoch);
      final success = await pendingRequest.completion.future.timeout(
        confirmationTimeout,
        onTimeout: () => false,
      );
      if (!success && epoch == _epoch) {
        final text = control == ScooterControl.kickStart
            ? "Kick start wasn't confirmed. This model, firmware or region may restrict changes."
            : "${control.label} wasn't confirmed. The last reported value is still shown.";
        if (request.changesSettings) {
          tuningNotice = text;
          configRevision++;
        }
        _message(text);
      }
      return success && epoch == _epoch;
    } catch (error) {
      if (epoch == _epoch) {
        _message('${control.label}: ${ScooterController._error(error)}');
        configRevision++;
      }
      return false;
    } finally {
      if (identical(_pending[control], pendingRequest)) {
        _pending.remove(control);
      }
      _changed();
    }
  }

  Future<bool> toggle(
    ScooterControl control,
    Reading reading,
    String label,
  ) async {
    final current = telemetry.flag(reading);
    if (current == null) {
      _message('Waiting for scooter status.');
      return false;
    }
    return _confirmed(ScooterCommand(control, value: current ? 0 : 1));
  }

  Future<bool> toggleLock() =>
      toggle(ScooterControl.lock, Reading.locked, 'Lock');
  Future<bool> setGear(int value) async {
    if (value < 1 || value > 3) return false;
    if (telemetry.availableGears != null &&
        !telemetry.availableGears!.contains(value)) {
      _message('This gear is not available on this scooter.');
      return false;
    }
    return _confirmed(ScooterCommand(ScooterControl.gear, value: value));
  }

  Future<bool> setMiles(bool value) =>
      _confirmed(ScooterCommand(ScooterControl.unit, value: value ? 1 : 0));
  Future<bool> setConfig(ScooterControl control, int value) async {
    final bounds = range(control);
    if (bounds == null) return false;
    final requested = bounds.clamp(value);
    tuningNotice = null;
    final result = await _confirmed(ScooterCommand(control, value: requested));
    if (control == ScooterControl.maxSpeed &&
        result &&
        telemetry.integer(Reading.maxSpeed) != requested) {
      tuningNotice =
          'Requested $requested km/h. Scooter reported ${telemetry.integer(Reading.maxSpeed)} km/h; its firmware may restrict the limit.';
      _changed();
    }
    return result;
  }

  static const _settings = [
    ScooterControl.maxSpeed,
    ScooterControl.startTorque,
    ScooterControl.maxTorque,
    ScooterControl.brake,
  ];
  Future<void> readSettings() async {
    if (!ready || readingSettings) return;
    final epoch = _epoch;
    readingSettings = true;
    _changed();
    for (final control in _settings.where(supportsControl)) {
      if (epoch != _epoch) break;
      await _confirmed(
        ScooterCommand(control, operation: CommandOperation.read),
      );
    }
    if (epoch == _epoch) {
      readingSettings = false;
      _changed();
    }
  }

  Future<void> resetTuning() async {
    final epoch = _epoch;
    for (final control in _settings.where(supportsControl)) {
      if (epoch != _epoch || !ready) return;
      if (!await _confirmed(
        ScooterCommand(control, operation: CommandOperation.reset),
      )) {
        return;
      }
    }
    if (epoch == _epoch) await readSettings();
  }

  Future<void> queryVersions() async {
    await _confirmed(
      const ScooterCommand(
        ScooterControl.version,
        operation: CommandOperation.read,
      ),
    );
  }

  Future<void> queryWorkMode() async {
    await _confirmed(
      const ScooterCommand(
        ScooterControl.workMode,
        operation: CommandOperation.read,
      ),
    );
  }

  Future<void> setWorkMode(int value) async {
    await _confirmed(ScooterCommand(ScooterControl.workMode, value: value));
  }

  Future<void> findScooter() async {
    await _confirmed(const ScooterCommand(ScooterControl.find, value: 1));
  }

  Future<void> setAmbient(int mode, [int hue = 0]) async {
    await _confirmed(
      ScooterCommand(ScooterControl.ambient, value: mode, data: [hue]),
    );
  }

  Future<void> pulse(ScooterControl control) async {
    if (!{
      ScooterControl.seat,
      ScooterControl.helmet,
      ScooterControl.storage,
      ScooterControl.brakeLock,
    }.contains(control)) {
      return;
    }
    final value = _pulseValues[control] == 1 ? 2 : 1;
    if (await _confirmed(ScooterCommand(control, value: value))) {
      _pulseValues[control] = value;
      _message('Control acknowledged. Check the compartment itself.');
    }
  }

  Future<void> sendRaw(int code, List<int> data) async {
    if (!canControl) {
      _message('Connect and unlock the scooter first.');
      return;
    }
    try {
      final request = _session!.request(
        ScooterCommand(ScooterControl.raw, value: code, data: data),
        telemetry,
      );
      if (request == null) {
        throw StateError('Raw commands are unavailable for this integration.');
      }
      if (isDemo) {
        _log('DEMO', 'Raw $code: ${HexBytes.format(data)} (not sent)');
        _changed();
        return;
      }
      await _queueWrite(() {
        if (!canControl) {
          throw StateError('Connect and unlock the scooter first.');
        }
        return request.encode(telemetry);
      }, _epoch);
      _changed();
    } catch (error) {
      _message(ScooterController._error(error));
    }
  }
}
