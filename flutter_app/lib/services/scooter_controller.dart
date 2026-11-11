import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show PlatformException, MissingPluginException;

import '../catalog/local_scooter_database.dart';
import '../catalog/scooter_catalog.dart';
import '../core/hex_bytes.dart';
import '../core/telemetry.dart';
import '../integrations/protocol_registry.dart';
import '../integrations/scooter_protocol.dart';
import '../models/scooter_control.dart';
import 'ble_transport.dart';
import 'preferences.dart';
import 'phone_speed.dart';
export '../models/scooter_control.dart';
part 'scooter_commands.dart';
part 'scooter_models.dart';
part 'scooter_connection.dart';

enum LinkPhase { idle, scanning, connecting, ready }

class FrameEntry {
  FrameEntry(this.direction, this.message, {this.fields = const {}})
    : at = DateTime.now();
  final DateTime at;
  final String direction, message;
  final Map<String, Object?> fields;
  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'direction': direction,
    'message': message,
    if (fields.isNotEmpty) 'fields': fields,
  };
}

class _Pending {
  _Pending(this.accepts);
  final bool Function(ProtocolEvent) accepts;
  final completion = Completer<bool>();
  void complete(bool value) {
    if (!completion.isCompleted) completion.complete(value);
  }
}

class ScooterController extends ChangeNotifier {
  ScooterController({
    required this.transport,
    required this.preferences,
    Future<void> Function()? permissions,
    ProtocolRegistry? registry,
    ScooterCatalog? catalog,
    PhoneSpeedProvider? phoneSpeedProvider,
    this.confirmationTimeout = const Duration(seconds: 3),
    this.sessionResponseTimeout = const Duration(seconds: 8),
    this.reconnectDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ],
    this.telemetryRefreshInterval = const Duration(milliseconds: 100),
    this.scanCooldown = const Duration(seconds: 3),
  }) : _permissions = permissions ?? requestScooterPermissions,
       registry = registry ?? ProtocolRegistry.standard(),
       catalog = catalog ?? ScooterCatalog([]),
       database = LocalScooterDatabase(preferences),
       phoneSpeed = PhoneSpeedMonitor(
         phoneSpeedProvider ?? NativePhoneSpeedProvider(),
       ) {
    speedSource = SpeedSource.values.firstWhere(
      (v) => v.name == preferences.read('speedSource'),
      orElse: () => SpeedSource.scooter,
    );
    themePreset = AppThemePreset.values.firstWhere(
      (v) => v.name == preferences.read('themePreset'),
      orElse: () => AppThemePreset.ocean,
    );
    customThemeColor =
        0xff000000 |
        ((int.tryParse(preferences.read('customThemeColor') ?? '', radix: 16) ??
                0x2563eb) &
            0xffffff);
    phoneSpeed.addListener(_changed);
    appearance = AppAppearance.values.firstWhere(
      (v) => v.name == preferences.read('appearance'),
      orElse: () => AppAppearance.system,
    );
    final old = SavedScooter.decode(preferences.read('scooter'));
    // Existing installs only supported this integration. Preserve renamed reconnects.
    saved = old == null
        ? null
        : SavedScooter(
            old.id,
            old.name,
            advertisedName: old.advertisedName,
            protocolId: old.protocolId ?? 'vicont',
            profileId: old.profileId,
          );
    fahrenheit = preferences.read('temperatureUnit') == 'fahrenheit';
    autoReconnect = preferences.read('autoReconnect') != 'false';
    hasSeenSetup = saved != null || preferences.read('setupSeen') == 'true';
    setupNamePending = preferences.read('setupNamePending') == 'true';
    setupComplete =
        !setupNamePending &&
        (saved != null || preferences.read('setupComplete') == 'true');
    if (saved != null) {
      _protocol = this.registry.byId(saved!.protocolId);
      evidence = ScooterEvidence(
        protocolId: saved!.protocolId!,
        advertisedName: saved!.advertisedName ?? '',
      );
      _resolveModel();
    }
    _applyFeatures();
    _notifySub = transport.notifications.listen(
      _onBytes,
      onError: (Object error) {
        if (ready || phase == LinkPhase.connecting) {
          _log('ERROR', 'Bluetooth notifications stopped: ${_error(error)}');
          _message(
            'Bluetooth notifications stopped. Reconnect to the scooter.',
          );
          unawaited(_connectionLost());
        }
      },
    );
    _disconnectSub = transport.disconnected.listen((_) {
      if (ready || phase == LinkPhase.connecting) {
        _log('LINK', 'Bluetooth link disconnected.');
        _message('Scooter disconnected.');
        unawaited(_connectionLost());
      }
    });
  }
  final ScooterTransport transport;
  final PreferenceStore preferences;
  final ProtocolRegistry registry;
  final ScooterCatalog catalog;
  final LocalScooterDatabase database;
  final PhoneSpeedMonitor phoneSpeed;
  SpeedSource speedSource = SpeedSource.scooter;
  AppThemePreset themePreset = AppThemePreset.ocean;
  int customThemeColor = 0xff2563eb, themeRevision = 0;
  int get themeColor => themePreset == AppThemePreset.custom
      ? customThemeColor
      : themePreset.color;
  bool selectingSpeedSource = false;
  DateTime? _scooterSpeedAt;
  Timer? _speedExpiry;
  SpeedEstimate get displaySpeedEstimate {
    final value = telemetry[Reading.speed]?.toDouble();
    if (isDemo) return SpeedEstimate(value, 'Demo');
    if (speedSource == SpeedSource.scooter) {
      return SpeedEstimate(value, 'Scooter');
    }
    final fresh =
        _scooterSpeedAt != null &&
        DateTime.now().difference(_scooterSpeedAt!) <=
            const Duration(seconds: 3);
    return estimateSpeed(
      speedSource,
      fresh && value != null && value.isFinite && value >= 0 ? value : null,
      phoneSpeed.sample,
    );
  }

  void _syncPhoneSpeed() {
    phoneSpeed.setEnabled(
      _appActive && ready && !isDemo && speedSource != SpeedSource.scooter,
    );
    _scheduleSpeedExpiry();
  }

  void _scheduleSpeedExpiry() {
    _speedExpiry?.cancel();
    if (speedSource != SpeedSource.mixed ||
        !_appActive ||
        !ready ||
        isDemo ||
        _scooterSpeedAt == null) {
      return;
    }
    final remaining =
        const Duration(seconds: 3) -
        DateTime.now().difference(_scooterSpeedAt!);
    if (!remaining.isNegative) _speedExpiry = Timer(remaining, _changed);
  }

  Future<void> setSpeedSource(SpeedSource value) async {
    if (selectingSpeedSource) return;
    selectingSpeedSource = true;
    _changed();
    try {
      if (value != SpeedSource.scooter) await phoneSpeed.provider.authorize();
      if (_closed) return;
      speedSource = value;
      _syncPhoneSpeed();
      await _persist('speedSource', value.name);
    } catch (error) {
      final detail = error is PlatformException
          ? error.message ?? 'Location is unavailable.'
          : error is MissingPluginException
          ? 'Use the Android or iOS app.'
          : _error(error);
      _message('Phone speed: $detail');
    } finally {
      selectingSpeedSource = false;
      _changed();
    }
  }

  Future<void> setThemePreset(AppThemePreset value, {int? color}) async {
    if (color != null) customThemeColor = 0xff000000 | (color & 0xffffff);
    themePreset = value;
    themeRevision++;
    _changed();
    if (color != null) {
      await _persist('customThemeColor', customThemeColor.toRadixString(16));
    }
    await _persist('themePreset', value.name);
  }

  final Future<void> Function() _permissions;
  final Duration confirmationTimeout, telemetryRefreshInterval, scanCooldown;
  final Duration sessionResponseTimeout;
  final List<Duration> reconnectDelays;
  Timer? _reconnectTimer;
  bool _lifecycleStarted = false, _appActive = true;
  bool _reconnectPaused = false, _autoConnecting = false;
  int _reconnectAttempt = 0;
  bool fahrenheit = false, autoReconnect = true;
  bool hasSeenSetup = false, setupComplete = false;
  bool setupNamePending = false;
  bool get reconnecting => _autoConnecting || _reconnectTimer != null;
  Completer<bool>? _sessionResponse;
  late final StreamSubscription<List<int>> _notifySub;
  late final StreamSubscription<void> _disconnectSub;
  StreamSubscription<NearbyScooter>? _scanSub;
  Timer? _scanTimer, _telemetryTimer;
  final _pending = <ScooterControl, _Pending>{};
  final _nearby = <String, NearbyScooter>{};
  final _logs = ListQueue<FrameEntry>();
  List<NearbyScooter>? _nearbySnapshot;
  List<FrameEntry>? _logSnapshot;
  Map<String, Object?> _connectionDetails = const {};
  Map<String, Object?> _previousConnectionDetails = const {};
  Future<void> _writeTail = Future.value();
  bool _closed = false;
  int _epoch = 0;
  ScooterProtocol? _protocol;
  ProtocolSession? _session;
  String? _lastIdentity;
  LinkPhase phase = LinkPhase.idle;
  Telemetry telemetry = const Telemetry();
  ScooterEvidence? evidence;
  ScooterModel? model;
  bool modelAmbiguous = false, isDemo = false;
  String scooterName = 'Your scooter';
  String? connectedId;
  SavedScooter? saved;
  AppAppearance appearance = AppAppearance.system;
  final Map<Feature, bool> features = {};
  String? message, tuningNotice;
  int messageRevision = 0, configRevision = 0;
  bool readingSettings = false;
  DateTime? lastReceived, _lastScan;
  final _pulseValues = <ScooterControl, int>{};
  bool get ready => phase == LinkPhase.ready;
  bool get canControl => ready && telemetry.locked != true;
  String? get protocolId => _protocol?.id;
  String get protocolLabel => _protocol?.label ?? 'No integration selected';
  String get modelLabel => model?.name ?? 'Unidentified scooter';
  String get artwork => model?.artwork ?? 'assets/scooter.png';
  List<ScooterModel> get models => [...catalog.models, ...database.models];
  bool pending(ScooterControl control) => _pending.containsKey(control);
  bool supports(Feature feature) =>
      features[feature] == true && supportsControl(feature.control);
  bool supportsControl(ScooterControl control) =>
      (_protocol ?? registry.byId('vicont'))?.controls.contains(control) ==
      true;
  ControlRange? range(ScooterControl control) => _protocol?.ranges[control];
  List<FrameEntry> get logs =>
      _logSnapshot ??= List.unmodifiable(_logs.toList().reversed);
  List<NearbyScooter> get nearby => _nearbySnapshot ??= List.unmodifiable(
    _nearby.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)),
  );
  String exportLog() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    if (_connectionDetails.isNotEmpty) 'connection': _connectionDetails,
    if (_previousConnectionDetails.isNotEmpty)
      'previousConnection': _previousConnectionDetails,
    'entries': _logs.map((e) => e.toJson()).toList(),
  });
  void _changed() {
    if (!_closed) notifyListeners();
  }

  void _telemetryChanged() {
    _telemetryTimer ??= Timer(telemetryRefreshInterval, () {
      _telemetryTimer = null;
      _changed();
    });
  }

  void _message(String text) {
    message = text;
    messageRevision++;
    _changed();
  }

  void _log(
    String direction,
    String text, [
    Map<String, Object?> fields = const {},
  ]) {
    _logs.add(FrameEntry(direction, text, fields: Map.unmodifiable(fields)));
    if (_logs.length > 240) _logs.removeFirst();
    _logSnapshot = null;
  }

  void clearLog() {
    _logs.clear();
    _logSnapshot = null;
    _changed();
  }

  Future<void> _persist(String key, String? value) =>
      _save(preferences.write(key, value));
  Future<void> _save(Future<void> write) async {
    try {
      await write;
    } catch (_) {
      _message('This preference could not be saved. Please try again.');
    }
  }

  Future<void> scan() async {
    if (ready || phase == LinkPhase.connecting || phase == LinkPhase.scanning) {
      return;
    }
    _pauseReconnect();
    if (_lastScan != null &&
        DateTime.now().difference(_lastScan!) < scanCooldown) {
      _message('Give Bluetooth a moment before scanning again.');
      return;
    }
    final epoch = ++_epoch;
    phase = LinkPhase.scanning;
    _nearby.clear();
    _nearbySnapshot = null;
    _changed();
    try {
      await _permissions();
      if (epoch != _epoch) return;
      await transport.prepare();
      if (epoch != _epoch) return;
      _lastScan = DateTime.now();
      _scanSub = transport.scan().listen(
        (device) {
          if (epoch != _epoch || !registry.accepts(device)) return;
          final previous = _nearby[device.id];
          if (previous != null &&
              previous.name == device.name &&
              (previous.rssi - device.rssi).abs() < 4 &&
              listEquals(previous.serviceUuids, device.serviceUuids) &&
              listEquals(previous.manufacturerData, device.manufacturerData)) {
            return;
          }
          _nearby[device.id] = device;
          _nearbySnapshot = null;
          _changed();
        },
        onError: (Object error) {
          if (epoch == _epoch) {
            _message(_error(error));
            unawaited(stopScan());
          }
        },
      );
      _scanTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(stopScan()),
      );
    } catch (error) {
      if (epoch == _epoch) {
        phase = LinkPhase.idle;
        _message(_error(error));
      }
    }
  }

  Future<void> stopScan() async {
    final epoch = _epoch;
    _scanTimer?.cancel();
    _scanTimer = null;
    final subscription = _scanSub;
    _scanSub = null;
    await subscription?.cancel();
    if (epoch == _epoch && phase == LinkPhase.scanning) {
      _epoch++;
      phase = LinkPhase.idle;
      _changed();
    }
  }

  Future<void> connect(
    SavedScooter device, {
    bool automatic = false,
    bool nameDuringSetup = false,
  }) async {
    if (phase == LinkPhase.connecting) return;
    if (!automatic) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectAttempt = 0;
      _reconnectPaused = false;
    }
    final advertisement =
        _nearby[device.id] ??
        NearbyScooter(device.id, device.advertisedName ?? device.name, 0);
    final previous = saved?.id == device.id ? saved : null;
    final disconnecting = disconnect(keepReconnect: true);
    final epoch = _epoch;
    phase = LinkPhase.connecting;
    scooterName = previous?.name ?? device.name;
    connectedId = device.id;
    _changed();
    try {
      // Reserve the session before yielding so rapid taps cannot connect twice.
      await disconnecting;
      if (epoch != _epoch) return;
      _protocol = registry.resolve(
        advertisement,
        protocolId: device.protocolId ?? previous?.protocolId,
      );
      _session = _protocol!.createSession();
      if (_connectionDetails['layout'] != null) {
        _previousConnectionDetails = _connectionDetails;
      }
      _connectionDetails = {
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'protocolId': _protocol!.id,
      };
      final response = Completer<bool>();
      _sessionResponse = response;
      evidence = ScooterEvidence(
        protocolId: _protocol!.id,
        advertisedName: advertisement.name,
      );
      if (previous != null) await database.migrateLegacy(device.id);
      if (epoch != _epoch) return;
      _resolveModel();
      _applyFeatures();
      _log('TYPE', 'Bluetooth integration selected: $protocolLabel.', {
        'event': 'protocol_selected',
        ...evidence!.toJson(),
      });
      await _permissions();
      if (epoch != _epoch) return;
      await transport.prepare();
      if (epoch != _epoch) return;
      await transport.connect(device.id, profile: _protocol!.connection);
      if (epoch != _epoch) return;
      _updateEvidence();
      final channel = transport.selection;
      _connectionDetails = {
        ..._connectionDetails,
        ...transport.diagnostics,
        'layout': channel?.layoutId,
        'notifyService': channel?.notifyService,
        'notify': channel?.notify,
        'writeService': channel?.writeService,
        'write': channel?.write,
        'writeMode': channel?.writeMode.name,
        'services': [
          for (final service in transport.discoveredServices)
            {
              'uuid': service.id,
              'characteristics': [
                for (final c in service.characteristics)
                  {
                    'uuid': c.id,
                    'notify': c.notify,
                    'writeWithResponse': c.writeWithResponse,
                    'writeWithoutResponse': c.writeWithoutResponse,
                  },
              ],
            },
        ],
      };
      _log(
        'LINK',
        'GATT configured; starting scooter handshake.',
        _connectionDetails,
      );
      for (final frame in _session!.handshake) {
        await _writeRaw(frame, epoch);
      }
      if (epoch != _epoch) return;
      if (_protocol!.connection.requiresResponse) {
        final answered = await response.future.timeout(
          sessionResponseTimeout,
          onTimeout: () => false,
        );
        if (epoch != _epoch) return;
        if (!answered) {
          throw StateError(
            'Bluetooth connected, but the scooter did not answer the handshake. '
            'Reconnect and copy the Diagnostics log if this repeats.',
          );
        }
      }
      if (epoch != _epoch) return;
      if (nameDuringSetup) {
        setupNamePending = true;
        setupComplete = false;
        await _persist('setupNamePending', 'true');
        if (epoch != _epoch) return;
      }
      phase = LinkPhase.ready;
      _syncPhoneSpeed();
      saved = SavedScooter(
        device.id,
        scooterName,
        advertisedName: advertisement.name,
        protocolId: _protocol!.id,
        profileId: database.profileId(device.id),
      );
      _log('INFO', 'Scooter session ready.');
      _sendReactions();
      _changed();
      _recordIdentity();
      await _persist('scooter', saved!.encode());
      if (epoch != _epoch) return;
      setupComplete = !setupNamePending;
      hasSeenSetup = true;
      _reconnectAttempt = 0;
      await _persist('setupComplete', '$setupComplete');
      await _persist('setupSeen', 'true');
      if (epoch == _epoch) unawaited(queryVersions());
    } catch (error) {
      if (epoch == _epoch) {
        _log('ERROR', 'Connection failed: ${_error(error)}');
        _message(_error(error));
        await disconnect(keepReconnect: automatic);
      }
    }
  }

  Future<void> startDemo() async {
    final disconnecting = disconnect();
    final epoch = _epoch;
    await disconnecting;
    if (epoch != _epoch || _closed) return;
    isDemo = true;
    phase = LinkPhase.ready;
    _syncPhoneSpeed();
    scooterName = 'City runner';
    _protocol = ProtocolRegistry.standard().byId('vicont');
    _session = _protocol!.createSession();
    telemetry = Telemetry.demo;
    evidence = null;
    model = null;
    _applyFeatures();
    configRevision++;
    _log(
      'DEMO',
      'Local simulation. No Bluetooth writes or model observations.',
    );
    _changed();
  }

  Future<void> disconnect({bool keepReconnect = false}) async {
    if (!keepReconnect) _pauseReconnect();
    final epoch = ++_epoch;
    if (_sessionResponse?.isCompleted == false) {
      _sessionResponse!.complete(false);
    }
    _sessionResponse = null;
    phase = LinkPhase.idle;
    _syncPhoneSpeed();
    _speedExpiry?.cancel();
    _scooterSpeedAt = null;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    for (final request in _pending.values) {
      request.complete(false);
    }
    _pending.clear();
    isDemo = false;
    connectedId = null;
    telemetry = const Telemetry();
    _session = null;
    _protocol = null;
    evidence = null;
    model = null;
    modelAmbiguous = false;
    _lastIdentity = null;
    _pulseValues.clear();
    lastReceived = null;
    tuningNotice = null;
    readingSettings = false;
    configRevision++;
    _changed();
    await stopScan();
    // Scan cancellation can finish after a newer connection has taken over.
    if (epoch != _epoch) return;
    await transport.disconnect();
  }

  Future<void> forget() async {
    final id = saved?.id;
    await disconnect();
    saved = null;
    setupNamePending = false;
    if (id != null) await _save(database.forget(id));
    await _persist('scooter', null);
    await _persist('setupNamePending', null);
    _changed();
  }

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    scooterName = trimmed.substring(0, trimmed.length.clamp(0, 32));
    if (!isDemo && connectedId != null) {
      saved = SavedScooter(
        connectedId!,
        scooterName,
        advertisedName: evidence?.advertisedName,
        protocolId: protocolId,
        profileId: database.profileId(connectedId!),
      );
      await _persist('scooter', saved!.encode());
    }
    _changed();
  }

  Future<void> finishSetupWithName(String name) async {
    if (!ready || isDemo || name.trim().isEmpty) return;
    final epoch = _epoch;
    final named = SavedScooter(
      connectedId!,
      String.fromCharCodes(name.trim().runes.take(32)),
      advertisedName: evidence?.advertisedName,
      protocolId: protocolId,
      profileId: database.profileId(connectedId!),
    );
    try {
      await preferences.write('scooter', named.encode());
      if (epoch != _epoch) return;
      await preferences.write('setupComplete', 'true');
      if (epoch != _epoch) return;
      // Clear the resume marker last, only after the named record is durable.
      await preferences.write('setupNamePending', 'false');
    } catch (_) {
      if (epoch == _epoch) {
        _message('The scooter name could not be saved. Please try again.');
      }
      return;
    }
    if (epoch != _epoch) return;
    scooterName = named.name;
    saved = named;
    setupNamePending = false;
    setupComplete = true;
    _changed();
  }

  Future<void> setAppearance(AppAppearance value) async {
    appearance = value;
    _changed();
    await _persist('appearance', value.name);
  }

  Future<void> setFahrenheit(bool value) async {
    fahrenheit = value;
    _changed();
    await _persist('temperatureUnit', value ? 'fahrenheit' : 'celsius');
  }

  Future<void> _writeRaw(List<int> bytes, int epoch) =>
      _queueWrite(() => bytes, epoch);
  Future<void> _queueWrite(List<int> Function() encode, int epoch) {
    final write = _writeTail.catchError((Object _) {}).then((_) async {
      if (epoch != _epoch || _closed) throw StateError('Connection changed.');
      final bytes = encode();
      _log('TX', HexBytes.format(bytes));
      try {
        await transport.write(bytes);
      } catch (error) {
        _log('ERROR', 'Bluetooth write failed: ${_error(error)}');
        rethrow;
      }
    });
    _writeTail = write;
    return write;
  }

  void _onBytes(List<int> bytes) {
    if (_closed || isDemo || (!ready && phase != LinkPhase.connecting)) return;
    final session = _session;
    if (session == null) return;
    final wasLocked = telemetry.locked;
    // Preserve notification boundaries and incomplete/unrecognized packets.
    // Parsed-only logs hid the evidence needed to diagnose a silent session.
    _log('RX-RAW', HexBytes.format(bytes));
    var received = false;
    for (final event in session.decode(bytes, telemetry)) {
      if (event.diagnostic != null) _log('RX', event.diagnostic!);
      if (event.diagnosticOnly) continue;
      received = true;
      final previousSpeed = telemetry[Reading.speed];
      telemetry = event.telemetry;
      if (event.speedReported ||
          (telemetry[Reading.speed] != null &&
              telemetry[Reading.speed] != previousSpeed)) {
        _scooterSpeedAt = DateTime.now();
        _scheduleSpeedExpiry();
      }
      lastReceived = DateTime.now();
      if (event.isSessionResponse && _sessionResponse?.isCompleted == false) {
        _sessionResponse!.complete(true);
      }
      if (event.settingsChanged) configRevision++;
      for (final pending in _pending.values.toList()) {
        if (pending.accepts(event)) pending.complete(true);
      }
      if (event.identityChanged) {
        _updateEvidence();
        _recordIdentity();
      }
      if (ready) _sendReactions();
    }
    if (received) {
      if (telemetry.locked != wasLocked) {
        // Lock changes affect access to every route, not just a displayed value.
        _telemetryTimer?.cancel();
        _telemetryTimer = null;
        _changed();
      } else {
        _telemetryChanged();
      }
    }
  }

  void _sendReactions() {
    final session = _session;
    if (session == null) return;
    for (final command in session.reactions(telemetry)) {
      final request = session.request(command, telemetry);
      if (request == null) continue;
      unawaited(
        _queueWrite(() => request.encode(telemetry), _epoch).catchError((
          Object error,
        ) {
          _log('ERROR', 'Protocol acknowledgement failed: ${_error(error)}');
        }),
      );
    }
  }

  static String _error(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _speedExpiry?.cancel();
    phoneSpeed.removeListener(_changed);
    phoneSpeed.dispose();
    _reconnectTimer?.cancel();
    if (_sessionResponse?.isCompleted == false) {
      _sessionResponse!.complete(false);
    }
    _scanTimer?.cancel();
    _telemetryTimer?.cancel();
    for (final request in _pending.values) {
      request.complete(false);
    }
    _pending.clear();
    unawaited(_scanSub?.cancel());
    unawaited(_notifySub.cancel());
    unawaited(_disconnectSub.cancel());
    unawaited(transport.close());
    super.dispose();
  }
}
