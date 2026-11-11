import '../../ble/ble_models.dart';
import '../../core/telemetry.dart';
import '../../models/scooter_control.dart';
import '../scooter_protocol.dart';
import 'vicont_codec.dart';
import 'vicont_commands.dart';
import 'vicont_decoder.dart';

class VicontProtocol implements ScooterProtocol {
  @override
  String get id => 'vicont';
  @override
  String get label => 'Vicont family';
  @override
  bool matches(NearbyScooter advertisement) =>
      Protocol.prefixes.any(advertisement.name.toUpperCase().startsWith);
  @override
  BleConnectionProfile get connection => const BleConnectionProfile(
    layouts: [
      GattLayout(id: 'fff0-fff1', service: 'fff0', notify: 'fff1'),
      GattLayout(id: 'fee0-fee2', service: 'fee0', notify: 'fee2'),
    ],
    // The extracted client waits after enabling notifications before handshaking.
    notificationDelay: Duration(seconds: 1),
    writeDelay: Duration(milliseconds: 300),
    preferredMtu: 255,
    requiresResponse: true,
  );
  @override
  Set<Feature> get defaultFeatures => const {
    Feature.headlight,
    Feature.cruise,
    Feature.kickStart,
  };
  @override
  Set<ScooterControl> get controls => _controls;
  static final _controls = Set<ScooterControl>.unmodifiable(
    ScooterControl.values,
  );
  @override
  Map<ScooterControl, ControlRange> get ranges => const {
    ScooterControl.maxSpeed: ControlRange(
      Protocol.minSpeedKmh,
      Protocol.maxSpeedKmh,
    ),
    ScooterControl.startTorque: ControlRange(1, 10),
    ScooterControl.maxTorque: ControlRange(1, 10),
    ScooterControl.brake: ControlRange(0, 9),
  };
  @override
  ProtocolSession createSession() => _VicontSession();
}

class _VicontSession implements ProtocolSession {
  final _framer = NotificationFramer();
  (bool, bool)? _lastBindAck;
  @override
  List<List<int>> get handshake => Protocol.handshake;
  @override
  Iterable<ProtocolEvent> decode(List<int> bytes, Telemetry previous) sync* {
    var state = previous;
    final frames = _framer.add(bytes);
    if (_framer.discardedBytes > 0) {
      yield ProtocolEvent(
        state,
        diagnostic:
            'Discarded ${_framer.discardedBytes} out-of-alignment bytes; '
            'recovered at a checksum-valid Vicont packet.',
        diagnosticOnly: true,
      );
    }
    for (final frame in frames) {
      if (!frame.checksumOk) {
        yield ProtocolEvent(
          state,
          diagnostic:
              '${frame.code}: ${Protocol.hex(frame.data)} '
              '(checksum mismatch; ignored)',
          diagnosticOnly: true,
        );
        continue;
      }
      state = state.apply(frame);
      yield ProtocolEvent(
        state,
        token: frame,
        speedReported: frame.code == 16 && frame.data.length >= 6,
        diagnostic: frame.code != 16 && frame.code != 19
            ? '${frame.code}: ${Protocol.hex(frame.data)}'
            : null,
        settingsChanged:
            frame.code >= 60 && frame.code <= 63 && frame.data.isNotEmpty,
        identityChanged: frame.code == 18 || frame.code == 171,
        isSessionResponse: switch (frame.code) {
          1 => true,
          16 => frame.data.length >= 12,
          17 => frame.data.length >= 6,
          18 => frame.data.length >= 8,
          171 => frame.data.length >= 2,
          _ => false,
        },
      );
    }
  }

  @override
  ProtocolRequest? request(ScooterCommand command, Telemetry state) =>
      VicontCommands.request(command, state);
  @override
  Iterable<ScooterCommand> reactions(Telemetry state) sync* {
    final locked = state.locked, bound = state.flag(Reading.bound);
    if (locked == null || bound == null || locked == bound) return;
    final pair = (locked, bound);
    if (pair == _lastBindAck) return;
    _lastBindAck = pair;
    // The original cloud eligibility gate is unavailable; docs/ble/VICONT.md records this limit.
    yield ScooterCommand(ScooterControl.binding, value: locked ? 1 : 2);
  }

  @override
  Telemetry simulate(ScooterCommand command, Telemetry state) =>
      VicontCommands.simulate(command, state);
}
