import '../ble/ble_models.dart';
import 'scooter_protocol.dart';
import 'vicont/vicont_protocol.dart';

class ProtocolRegistry {
  ProtocolRegistry(Iterable<ScooterProtocol> protocols)
    : protocols = List.unmodifiable(protocols) {
    if (this.protocols.map((p) => p.id).toSet().length !=
        this.protocols.length) {
      throw ArgumentError('Protocol IDs must be unique.');
    }
  }
  factory ProtocolRegistry.standard() => ProtocolRegistry([VicontProtocol()]);
  final List<ScooterProtocol> protocols;
  ScooterProtocol? byId(String? id) =>
      protocols.where((p) => p.id == id).firstOrNull;
  bool accepts(NearbyScooter advertisement) =>
      protocols.any((p) => p.matches(advertisement));
  List<ScooterProtocol> matching(NearbyScooter advertisement) =>
      protocols.where((p) => p.matches(advertisement)).toList(growable: false);
  ScooterProtocol resolve(NearbyScooter advertisement, {String? protocolId}) {
    if (protocolId != null) {
      final selected = byId(protocolId);
      if (selected == null) {
        throw StateError(
          'This scooter needs an unavailable Bluetooth integration.',
        );
      }
      return selected;
    }
    final candidates = matching(advertisement);
    if (candidates.length != 1) {
      throw StateError(
        candidates.isEmpty ? 'No Bluetooth integration matches this scooter.' : 'More than one Bluetooth integration matches. Choose the correct protocol before connecting.',
      );
    }
    return candidates.single;
  }
}
