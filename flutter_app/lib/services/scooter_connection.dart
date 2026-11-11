part of 'scooter_controller.dart';

extension ScooterConnection on ScooterController {
  Future<void> markSetupSeen() async {
    if (hasSeenSetup) return;
    hasSeenSetup = true;
    await _persist('setupSeen', 'true');
  }

  /// Called once by the app shell. First-time setup never touches the radio.
  void startConnectionLifecycle() {
    if (_lifecycleStarted || _closed) return;
    _lifecycleStarted = true;
    unawaited(_reconnectNow());
  }

  void setAppActive(bool active) {
    _appActive = active;
    _syncPhoneSpeed();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!active) {
      if (_autoConnecting && !ready) {
        unawaited(disconnect(keepReconnect: true));
      }
    } else {
      _reconnectAttempt = 0;
      unawaited(_reconnectNow());
    }
    _changed();
  }

  bool get _mayReconnect =>
      _lifecycleStarted &&
      _appActive &&
      !_closed &&
      autoReconnect &&
      !_reconnectPaused &&
      !isDemo &&
      !ready &&
      saved != null &&
      phase == LinkPhase.idle;

  void _pauseReconnect() {
    _reconnectPaused = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> setAutoReconnect(bool enabled) async {
    autoReconnect = enabled;
    if (!enabled) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      if (_autoConnecting && !ready) await disconnect();
    } else {
      _reconnectPaused = false;
      _reconnectAttempt = 0;
      unawaited(_reconnectNow());
    }
    _changed();
    await _persist('autoReconnect', '$enabled');
  }

  Future<void> _connectionLost() async {
    await disconnect(keepReconnect: true);
    _scheduleReconnect();
  }

  Future<void> _reconnectNow() async {
    if (!_mayReconnect || _autoConnecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _autoConnecting = true;
    _changed();
    _log('LINK', 'Reconnecting to saved scooter.', {
      'event': 'auto_reconnect',
      'attempt': _reconnectAttempt + 1,
    });
    try {
      await connect(saved!, automatic: true);
    } finally {
      _autoConnecting = false;
      _changed();
      if (!ready) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_mayReconnect ||
        _autoConnecting ||
        _reconnectTimer != null ||
        _reconnectAttempt >= reconnectDelays.length) {
      return;
    }
    final delay = reconnectDelays[_reconnectAttempt++];
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_reconnectNow());
    });
    _changed();
  }
}
