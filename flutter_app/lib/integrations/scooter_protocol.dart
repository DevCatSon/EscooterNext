import '../ble/ble_models.dart';
import '../core/telemetry.dart';
import '../models/scooter_control.dart';

abstract interface class ScooterProtocol {
  String get id;
  String get label;
  bool matches(NearbyScooter advertisement);
  BleConnectionProfile get connection;
  Set<Feature> get defaultFeatures;
  Set<ScooterControl> get controls;
  Map<ScooterControl, ControlRange> get ranges;
  ProtocolSession createSession();
}

/// A fresh session owns every protocol's parser, sync state and acknowledgements.
abstract interface class ProtocolSession {
  List<List<int>> get handshake;
  Iterable<ProtocolEvent> decode(List<int> bytes, Telemetry previous);
  ProtocolRequest? request(ScooterCommand command, Telemetry state);
  Iterable<ScooterCommand> reactions(Telemetry state);
  Telemetry simulate(ScooterCommand command, Telemetry state);
}

class ProtocolEvent {
  const ProtocolEvent(
    this.telemetry, {
    this.token,
    this.diagnostic,
    this.settingsChanged = false,
    this.identityChanged = false,
    this.isSessionResponse = false,
    this.diagnosticOnly = false,
    this.speedReported = false,
  });
  final Telemetry telemetry;
  final Object? token;
  final String? diagnostic;
  final bool settingsChanged, identityChanged;

  /// A recognizable reply to connection setup or a complete live report.
  final bool isSessionResponse;

  /// Rejected input may be logged without changing link health or device state.
  final bool diagnosticOnly;
  final bool speedReported;
}

class ProtocolRequest {
  const ProtocolRequest({
    required this.control,
    required this.encode,
    required this.accepts,
    this.readOnly = false,
    this.allowedWhileLocked = false,
    this.changesSettings = false,
  });
  final ScooterControl control;
  final List<int> Function(Telemetry latest) encode;
  final bool Function(ProtocolEvent event) accepts;
  final bool readOnly, allowedWhileLocked, changesSettings;
}
