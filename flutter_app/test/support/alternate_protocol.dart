import 'package:escooter_control/ble/ble_models.dart';
import 'package:escooter_control/core/telemetry.dart';
import 'package:escooter_control/integrations/scooter_protocol.dart';
import 'package:escooter_control/models/scooter_control.dart';

/// Synthetic test protocol. This does not claim support for a real scooter.
class AlternateProtocol implements ScooterProtocol {
  AlternateProtocol({this.prefix = 'OTHER'});
  final String prefix;
  @override
  String get id => 'test-alternate';
  @override
  String get label => 'Alternate fixture';
  @override
  bool matches(NearbyScooter ad) => ad.name.startsWith(prefix);
  @override
  BleConnectionProfile get connection => const BleConnectionProfile(
    layouts: [
      GattLayout(
        id: 'alternate',
        service: '1234',
        notify: '1235',
        writeService: '2345',
        write: '2346',
      ),
    ],
  );
  @override
  Set<Feature> get defaultFeatures => const {Feature.headlight};
  @override
  Set<ScooterControl> get controls => const {ScooterControl.headlight};
  @override
  Map<ScooterControl, ControlRange> get ranges => const {};
  @override
  ProtocolSession createSession() => _Session();
}

class _Session implements ProtocolSession {
  @override
  List<List<int>> get handshake => const [
    [0x12, 0x34],
  ];
  @override
  Iterable<ProtocolEvent> decode(List<int> bytes, Telemetry state) sync* {
    if (bytes.length == 4 && bytes[0] == 0xb1) {
      yield ProtocolEvent(
        state.withValues({
          Reading.battery: bytes[1],
          Reading.speed: bytes[2],
          Reading.headlight: bytes[3],
          Reading.locked: 0,
        }),
        token: 'alternate-status',
      );
    }
  }

  @override
  ProtocolRequest? request(ScooterCommand command, Telemetry state) {
    if (command.control != ScooterControl.headlight) return null;
    return ProtocolRequest(
      control: command.control,
      encode: (_) => [0x7e, command.value!],
      accepts: (event) =>
          event.token == 'alternate-status' &&
          event.telemetry[Reading.headlight] == command.value,
    );
  }

  @override
  Iterable<ScooterCommand> reactions(Telemetry state) => const [];
  @override
  Telemetry simulate(ScooterCommand command, Telemetry state) => state;
}
