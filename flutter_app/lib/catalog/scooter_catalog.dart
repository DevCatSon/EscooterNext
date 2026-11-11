import 'dart:convert';

import '../ble/ble_models.dart';
import '../models/scooter_control.dart';

class ScooterEvidence {
  const ScooterEvidence({
    required this.protocolId,
    required this.advertisedName,
    this.services = const [],
    this.layoutId,
    this.firmware = const {},
  });
  final String protocolId, advertisedName;
  final String? layoutId;
  final List<String> services;
  final Map<String, int> firmware;
  Map<String, Object?> toJson() => {
    'protocolId': protocolId,
    'advertisedName': advertisedName,
    'gattLayout': layoutId,
    'services': services,
    'firmware': firmware,
  };
}

class ScooterModel {
  const ScooterModel({
    required this.id,
    required this.name,
    required this.protocolId,
    required this.features,
    this.artwork = 'assets/scooter.png',
    this.advertisedNames = const [],
    this.namePrefixes = const [],
    this.requiredServices = const [],
    this.firmware = const {},
    this.source = 'catalogue',
  });
  final String id, name, protocolId, artwork, source;
  final Set<Feature> features;
  final List<String> advertisedNames, namePrefixes, requiredServices;
  final Map<String, int> firmware;
  bool get fallback =>
      advertisedNames.isEmpty &&
      namePrefixes.isEmpty &&
      requiredServices.isEmpty &&
      firmware.isEmpty;
  int? matchScore(ScooterEvidence evidence) {
    if (protocolId != evidence.protocolId) return null;
    final name = evidence.advertisedName.toUpperCase();
    if (advertisedNames.isNotEmpty &&
        !advertisedNames.any((n) => n.toUpperCase() == name)) {
      return null;
    }
    if (namePrefixes.isNotEmpty &&
        !namePrefixes.any((n) => name.startsWith(n.toUpperCase()))) {
      return null;
    }
    final services = evidence.services.map(normalizeUuid).toSet();
    if (!requiredServices.every((s) => services.contains(normalizeUuid(s)))) {
      return null;
    }
    if (!firmware.entries.every((e) => evidence.firmware[e.key] == e.value)) {
      return null;
    }
    // Explicit names outrank broad prefixes; additional evidence refines a match.
    return (advertisedNames.isNotEmpty ? 1000 : 0) +
        (namePrefixes.isEmpty
            ? 0
            : namePrefixes
                  .where((n) => name.startsWith(n.toUpperCase()))
                  .map((n) => n.length)
                  .reduce((a, b) => a > b ? a : b)) +
        requiredServices.length * 10 +
        firmware.length * 100;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocolId': protocolId,
    'artwork': artwork,
    'source': source,
    'features': features.map((f) => f.name).toList(),
    'advertisedNames': advertisedNames,
    'namePrefixes': namePrefixes,
    'requiredServices': requiredServices,
    'firmware': firmware,
  };
  factory ScooterModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String,
        name = json['name'] as String,
        protocol = json['protocolId'] as String;
    if (id.isEmpty || name.trim().isEmpty || protocol.isEmpty) {
      throw const FormatException('Model identity is missing.');
    }
    final artwork = json['artwork'] as String? ?? 'assets/scooter.png';
    if (!(artwork.startsWith('assets/') && !artwork.contains('..')) &&
        artwork != 'icon:scooter') {
      throw const FormatException(
        'Artwork must be a bundled asset or icon:scooter.',
      );
    }
    return ScooterModel(
      id: id,
      name: name,
      protocolId: protocol,
      artwork: artwork,
      source: json['source'] as String? ?? 'catalogue',
      features: Set.unmodifiable(
        (json['features'] as List).map(
          (f) => Feature.values.byName(f as String),
        ),
      ),
      advertisedNames: List<String>.unmodifiable(
        json['advertisedNames'] as List? ?? [],
      ),
      namePrefixes: List<String>.unmodifiable(
        json['namePrefixes'] as List? ?? [],
      ),
      requiredServices: List<String>.unmodifiable(
        json['requiredServices'] as List? ?? [],
      ),
      firmware: Map<String, int>.unmodifiable(
        Map<String, int>.from(json['firmware'] as Map? ?? {}),
      ),
    );
  }
}

class CatalogMatch {
  const CatalogMatch(this.model, {this.ambiguous = false});
  final ScooterModel? model;
  final bool ambiguous;
}

class ScooterCatalog {
  ScooterCatalog(Iterable<ScooterModel> models)
    : models = List.unmodifiable(models) {
    if (this.models.map((m) => m.id).toSet().length != this.models.length) {
      throw const FormatException('Duplicate model IDs.');
    }
  }
  factory ScooterCatalog.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported scooter catalogue version.');
    }
    return ScooterCatalog(
      (json['models'] as List).map(
        (m) => ScooterModel.fromJson(Map<String, dynamic>.from(m as Map)),
      ),
    );
  }
  final List<ScooterModel> models;
  ScooterModel? byId(String? id) => models.where((m) => m.id == id).firstOrNull;
  CatalogMatch match(ScooterEvidence evidence) {
    final scored =
        [for (final m in models) (m, m.matchScore(evidence))]
            .where((entry) => entry.$2 != null)
            .toList()
          ..sort((a, b) => b.$2!.compareTo(a.$2!));
    if (scored.isEmpty) return const CatalogMatch(null);
    if (scored.length > 1 && scored[0].$2 == scored[1].$2) {
      return const CatalogMatch(null, ambiguous: true);
    }
    return CatalogMatch(scored.first.$1);
  }
}
