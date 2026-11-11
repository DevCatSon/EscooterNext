part of 'scooter_controller.dart';

extension ScooterModels on ScooterController {
  void _resolveModel() {
    if (evidence == null) {
      model = null;
      modelAmbiguous = false;
      return;
    }
    final available = ScooterCatalog(models);
    final deviceId = connectedId ?? saved?.id ?? '';
    final selected = database.hasDevice(deviceId)
        ? database.profileId(deviceId)
        : saved?.id == deviceId
        ? saved?.profileId
        : null;
    final pinned = available.byId(selected);
    if (pinned != null && pinned.protocolId == protocolId) {
      model = pinned;
      modelAmbiguous = false;
      return;
    }
    final match = available.match(evidence!);
    model = match.model;
    modelAmbiguous = match.ambiguous;
  }

  void _applyFeatures() {
    final defaults =
        model?.features ??
        (_protocol ?? registry.byId('vicont'))?.defaultFeatures ??
        <Feature>{};
    final id = isDemo ? null : connectedId ?? saved?.id;
    final overrides = id == null ? <Feature, bool>{} : database.overrides(id);
    for (final f in Feature.values) {
      features[f] = overrides[f] ?? defaults.contains(f);
    }
  }

  Future<void> setFeature(Feature feature, bool enabled) async {
    features[feature] = enabled;
    _changed();
    final id = connectedId ?? saved?.id;
    if (!isDemo && id != null) {
      await _save(database.setFeature(id, feature, enabled));
    }
  }

  Future<void> resetFeatures() async {
    final id = connectedId ?? saved?.id;
    if (!isDemo && id != null) await _save(database.resetFeatures(id));
    _applyFeatures();
    _changed();
  }

  Future<void> selectModel(String? id) async {
    final deviceId = connectedId ?? saved?.id;
    if (deviceId == null || isDemo) return;
    final candidate = ScooterCatalog(models).byId(id);
    if (id != null &&
        (candidate == null || candidate.protocolId != protocolId)) {
      throw StateError('This model uses a different Bluetooth integration.');
    }
    final epoch = _epoch;
    await _save(database.setProfile(deviceId, id));
    if (epoch != _epoch || deviceId != (connectedId ?? saved?.id)) return;
    _resolveModel();
    _applyFeatures();
    if (saved?.id == deviceId) {
      saved = SavedScooter(
        deviceId,
        saved!.name,
        advertisedName: saved!.advertisedName,
        protocolId: saved!.protocolId,
        profileId: id,
      );
      await _persist('scooter', saved!.encode());
    }
    _recordIdentity(force: true);
    _changed();
  }

  Future<void> saveCurrentModel(String name, String artwork) async {
    if (isDemo || !ready || evidence == null || name.trim().isEmpty) return;
    final record = ScooterModel(
      id: database.models.any((m) => m.id == model?.id)
          ? model!.id
          : 'local-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      protocolId: protocolId!,
      features: Set.unmodifiable(Feature.values.where(supports)),
      artwork: artwork,
      advertisedNames: [evidence!.advertisedName],
      source: 'User-defined local model',
    );
    final epoch = _epoch;
    try {
      await _save(database.addModel(record));
    } catch (error) {
      _message(ScooterController._error(error));
      return;
    }
    if (epoch == _epoch) await selectModel(record.id);
  }

  void _updateEvidence() {
    if (evidence == null) return;
    final firmware = <String, int>{};
    for (final key in [
      Reading.instrumentHardware,
      Reading.instrumentSoftware,
      Reading.controllerHardware,
      Reading.controllerSoftware,
    ]) {
      final value = telemetry.integer(key);
      if (value != null) firmware[key.name] = value;
    }
    evidence = ScooterEvidence(
      protocolId: protocolId!,
      advertisedName: evidence!.advertisedName,
      layoutId: transport.selection?.layoutId,
      services: List.unmodifiable(
        transport.discoveredServices.map((s) => s.id),
      ),
      firmware: Map.unmodifiable(firmware),
    );
    _resolveModel();
    _applyFeatures();
  }

  void _recordIdentity({bool force = false}) {
    if (isDemo || connectedId == null || evidence == null || !ready) return;
    final fields = {
      'event': 'scooter_identified',
      ...evidence!.toJson(),
      'modelId': model?.id,
      'modelName': modelLabel,
      'modelSource': model?.source ?? 'unknown',
      'ambiguous': modelAmbiguous,
      'features': Feature.values.where(supports).map((f) => f.name).toList(),
    };
    final signature = jsonEncode(fields);
    if (!force && signature == _lastIdentity) return;
    _lastIdentity = signature;
    _log(
      'TYPE',
      'Scooter type: $modelLabel; protocol: $protocolLabel.',
      fields,
    );
    unawaited(
      _save(
        database.observe(
          connectedId!,
          evidence!,
          modelId: model?.id,
          modelName: modelLabel,
          ambiguous: modelAmbiguous,
        ),
      ),
    );
  }
}
