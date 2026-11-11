import 'dart:convert';

import '../services/preferences.dart';
import 'scooter_catalog.dart';

/// Bounded local records. Bluetooth IDs stay in storage, not exported model data.
class LocalScooterDatabase {
  LocalScooterDatabase(this.preferences) {
    final json = _read('scooter.database');
    if (json['schemaVersion'] == 1) {
      final records = json['models'];
      for (final record in records is List ? records : const []) {
        try {
          final model = ScooterModel.fromJson(
            Map<String, dynamic>.from(record as Map),
          );
          _models.removeWhere((m) => m.id == model.id);
          if (_models.length < 64) _models.add(model);
        } catch (_) {
          // One malformed record must not prevent other local models from loading.
        }
      }
      final devices = json['devices'], observations = json['observations'];
      if (devices is Map) _devices.addAll(Map<String, dynamic>.from(devices));
      if (observations is Map) {
        _observations.addAll(Map<String, dynamic>.from(observations));
      }
      _trimRecords();
    }
  }

  final PreferenceStore preferences;
  final List<ScooterModel> _models = [];
  final Map<String, dynamic> _devices = {}, _observations = {};
  Future<void> _writeTail = Future.value();
  List<ScooterModel> get models => List.unmodifiable(_models);
  int get observationCount => _observations.length;
  bool hasDevice(String id) => _devices.containsKey(id);
  Map<String, dynamic> _read(String key) {
    try {
      return jsonDecode(preferences.read(key) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _device(String id) =>
      _devices[id] is Map ? Map<String, dynamic>.from(_devices[id] as Map) : {};
  String? profileId(String id) {
    final value = _device(id)['profileId'];
    return value is String ? value : null;
  }

  Map<Feature, bool> overrides(String id) {
    final raw = _device(id)['features'];
    if (raw is! Map) return {};
    return {
      for (final f in Feature.values)
        if (raw[f.name] is bool) f: raw[f.name] as bool,
    };
  }

  Future<void> setFeature(String id, Feature feature, bool value) {
    final record = _device(id);
    final features = Map<String, dynamic>.from(
      record['features'] as Map? ?? {},
    );
    features[feature.name] = value;
    _devices[id] = {...record, 'features': features};
    return _save();
  }

  Future<void> resetFeatures(String id) {
    _devices[id] = {..._device(id)}..remove('features');
    return _save();
  }

  Future<void> setProfile(String id, String? profileId) {
    _devices[id] = {..._device(id), 'profileId': profileId};
    return _save();
  }

  Future<void> addModel(ScooterModel model) {
    if (_models.length >= 64 && !_models.any((m) => m.id == model.id)) {
      throw StateError('The local catalogue is full.');
    }
    _models.removeWhere((m) => m.id == model.id);
    _models.add(model);
    return _save();
  }

  Future<void> migrateLegacy(String id) async {
    if (_devices.containsKey(id)) return;
    final overrides = <String, bool>{};
    for (final f in Feature.values) {
      final value = preferences.read('feature.${f.name}');
      if (value == 'true' || value == 'false') {
        overrides[f.name] = value == 'true';
      }
    }
    _devices[id] = {'features': overrides};
    await _save();
  }

  Future<void> observe(
    String id,
    ScooterEvidence evidence, {
    String? modelId,
    String? modelName,
    bool ambiguous = false,
  }) {
    final old = _observations[id] is Map
        ? Map<String, dynamic>.from(_observations[id] as Map)
        : <String, dynamic>{};
    final now = DateTime.now().toUtc().toIso8601String();
    _observations.remove(id);
    _observations[id] = {
      ...evidence.toJson(),
      'modelId': modelId,
      'modelName': modelName,
      'ambiguous': ambiguous,
      'firstSeen': old['firstSeen'] ?? now,
      'lastSeen': now,
    };
    while (_observations.length > 128) {
      _observations.remove(_observations.keys.first);
    }
    return _save();
  }

  Future<void> forget(String id) {
    _devices.remove(id);
    _observations.remove(id);
    return _save();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'models': _models.map((m) => m.toJson()).toList(),
    'observations': _observations.values.toList(),
  });
  void _trimRecords() {
    while (_devices.length > 128) {
      _devices.remove(_devices.keys.first);
    }
    while (_observations.length > 128) {
      _observations.remove(_observations.keys.first);
    }
  }

  Future<void> _save() {
    _trimRecords();
    final snapshot = jsonEncode({
      'schemaVersion': 1,
      'models': _models.map((m) => m.toJson()).toList(),
      'devices': _devices,
      'observations': _observations,
    });
    final write = _writeTail
        .catchError((Object _) {})
        .then((_) => preferences.write('scooter.database', snapshot));
    _writeTail = write;
    return write;
  }
}
