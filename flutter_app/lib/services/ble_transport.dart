import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ble/ble_models.dart';
export '../ble/ble_models.dart';

abstract interface class ScooterTransport {
  Stream<List<int>> get notifications;
  Stream<void> get disconnected;
  Future<void> prepare();
  Stream<NearbyScooter> scan();
  Future<void> connect(String id, {required BleConnectionProfile profile});
  List<GattServiceInfo> get discoveredServices;
  GattSelection? get selection;
  Map<String, Object?> get diagnostics;
  Future<void> write(List<int> data);
  Future<void> disconnect();
  Future<void> close();
}

/// Permission prompts are only reached after an explicit Connect / Scan action.
Future<void> requestScooterPermissions() async {
  if (kIsWeb) {
    throw StateError('Bluetooth controls require the Android or iOS app.');
  }
  final List<Permission> permissions;
  if (defaultTargetPlatform == TargetPlatform.android) {
    final info = await DeviceInfoPlugin().androidInfo;
    permissions = info.version.sdkInt >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    // CoreBluetooth requests access when prepare() initializes the BLE plugin.
    // Avoid a second permission plugin whose SwiftPM flags depend on plist discovery.
    return;
  } else {
    throw StateError(
      'Use the Android or iOS app for Bluetooth. Demo Mode works without it.',
    );
  }
  final statuses = await permissions.request();
  if (statuses.values.any((status) => !status.isGranted)) {
    throw StateError(
      'Bluetooth access is needed to connect. You can allow it in your phone settings.',
    );
  }
}

class ReactiveScooterTransport implements ScooterTransport {
  ReactiveScooterTransport({
    FlutterReactiveBle Function()? createBle,
    this.readinessTimeout = const Duration(seconds: 30),
  }) : _createBle = createBle ?? FlutterReactiveBle.new;

  final FlutterReactiveBle Function() _createBle;
  final Duration readinessTimeout;
  // Constructing FlutterReactiveBle also initializes its native status observer.
  // Defer that work until prepare(), after the controller's permission request.
  late final _ble = _createBle();
  final _notifications = StreamController<List<int>>.broadcast();
  final _disconnected = StreamController<void>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifySubscription;
  Completer<void>? _connecting;
  Characteristic? _writeCharacteristic;
  Duration _writeDelay = Duration.zero;
  Timer? _writeCooldown;
  Completer<void>? _writeReady;
  int? _mtu;
  String? _mtuNotice;
  int _generation = 0;
  @override
  List<GattServiceInfo> discoveredServices = const [];
  @override
  GattSelection? selection;
  @override
  Map<String, Object?> get diagnostics => {
    'platform': defaultTargetPlatform.name,
    'mtu': _mtu,
    if (_mtuNotice != null) 'mtuNotice': _mtuNotice,
  };

  @override
  Stream<List<int>> get notifications => _notifications.stream;
  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  Future<void> prepare() async {
    await _ble.initialize();
    var lastStatus = BleStatus.unknown;
    final waitForAuthorizationUpdate =
        defaultTargetPlatform == TargetPlatform.android;
    // Android permission requests have already succeeded, but the BLE observer
    // can replay its pre-grant unauthorized state before emitting ready. On iOS,
    // CoreBluetooth owns the prompt, so unauthorized is a final denial instead.
    final status = await _ble.statusStream
        .where((value) {
          lastStatus = value;
          return value != BleStatus.unknown &&
              !(waitForAuthorizationUpdate && value == BleStatus.unauthorized);
        })
        .timeout(
          readinessTimeout,
          onTimeout: (sink) {
            sink.add(lastStatus);
            sink.close();
          },
        )
        .first;
    if (status != BleStatus.ready) {
      throw StateError(switch (status) {
        BleStatus.poweredOff => 'Turn Bluetooth on, then try again.',
        BleStatus.unauthorized =>
          'Allow Bluetooth access in your phone settings.',
        BleStatus.locationServicesDisabled =>
          'This Android version needs Location services enabled to scan.',
        BleStatus.unsupported => 'This device does not support Bluetooth LE.',
        _ => 'Bluetooth is not ready yet. Try again in a moment.',
      });
    }
  }

  @override
  Stream<NearbyScooter> scan() => _ble
      .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
      .map(
        (device) => NearbyScooter(
          device.id,
          device.name,
          device.rssi,
          serviceUuids: List.unmodifiable(
            device.serviceUuids.map((id) => id.toString()),
          ),
          manufacturerData: List.unmodifiable(device.manufacturerData),
        ),
      );

  @override
  Future<void> connect(
    String id, {
    required BleConnectionProfile profile,
  }) async {
    final disconnecting = disconnect();
    final generation = _generation;
    await disconnecting;
    if (generation != _generation) throw StateError('Connection cancelled.');
    final connected = Completer<void>();
    try {
      _connection = _ble
          .connectToDevice(
            id: id,
            connectionTimeout: const Duration(seconds: 18),
          )
          .listen(
            (update) {
              if (generation != _generation) return;
              if (update.connectionState == DeviceConnectionState.connected &&
                  !connected.isCompleted) {
                connected.complete();
              }
              if (update.connectionState ==
                  DeviceConnectionState.disconnected) {
                if (!connected.isCompleted) {
                  connected.completeError(
                    StateError(
                      'The scooter disconnected before setup finished.',
                    ),
                  );
                }
                _disconnected.add(null);
              }
            },
            onError: (Object error) {
              if (generation != _generation) return;
              if (!connected.isCompleted) connected.completeError(error);
              _disconnected.add(null);
            },
          );
      _connecting = connected;
      await connected.future.timeout(const Duration(seconds: 20));
      if (generation != _generation) throw StateError('Connection cancelled.');
      await _ble.discoverAllServices(id).timeout(const Duration(seconds: 8));
      if (generation != _generation) throw StateError('Connection cancelled.');
      final services = await _ble
          .getDiscoveredServices(id)
          .timeout(const Duration(seconds: 8));
      if (generation != _generation) throw StateError('Connection cancelled.');
      discoveredServices = List.unmodifiable(
        services.map(
          (service) => GattServiceInfo(
            service.id.toString(),
            List.unmodifiable(
              service.characteristics.map(
                (c) => GattCharacteristicInfo(
                  c.id.toString(),
                  notify: c.isNotifiable || c.isIndicatable,
                  writeWithResponse: c.isWritableWithResponse,
                  writeWithoutResponse: c.isWritableWithoutResponse,
                ),
              ),
            ),
          ),
        ),
      );
      selection = selectGattLayout(
        discoveredServices,
        profile,
        preferredWriteMode: defaultTargetPlatform == TargetPlatform.iOS
            ? GattWriteMode.withResponse
            : GattWriteMode.withoutResponse,
      );
      final selected = selection;
      if (selected == null) {
        throw StateError(
          'This device does not expose a compatible scooter service.',
        );
      }
      Characteristic characteristic(
        String serviceId,
        String characteristicId,
      ) => services
          .firstWhere((s) => s.id == Uuid.parse(normalizeUuid(serviceId)))
          .characteristics
          .firstWhere(
            (c) => c.id == Uuid.parse(normalizeUuid(characteristicId)),
          );
      final notify = characteristic(selected.notifyService, selected.notify);
      _writeCharacteristic = characteristic(
        selected.writeService,
        selected.write,
      );
      _writeDelay = profile.writeDelay;
      // Complete MTU negotiation before starting the CCCD subscription. Android
      // permits one GATT operation at a time; iOS negotiates its own MTU.
      if (defaultTargetPlatform == TargetPlatform.android &&
          profile.preferredMtu != null) {
        try {
          final mtu = await _ble
              .requestMtu(deviceId: id, mtu: profile.preferredMtu!)
              .timeout(const Duration(seconds: 2));
          if (generation == _generation) _mtu = mtu;
        } catch (error) {
          // Small command frames still fit the default MTU, as in the old client.
          if (generation == _generation) _mtuNotice = error.toString();
        }
      }
      if (generation != _generation) throw StateError('Connection cancelled.');
      _notifySubscription = notify.subscribe().listen(
        (bytes) {
          if (generation == _generation) _notifications.add(bytes);
        },
        onError: (Object error) {
          if (generation == _generation) {
            _notifications.addError(error);
            _disconnected.add(null);
          }
        },
      );
      if (profile.notificationDelay > Duration.zero) {
        await Future<void>.delayed(profile.notificationDelay);
      }
      if (generation != _generation) throw StateError('Connection cancelled.');
      _startWriteCooldown();
    } catch (_) {
      // A failed setup owns its cleanup, but must never close a newer attempt.
      if (generation == _generation) await disconnect();
      rethrow;
    } finally {
      if (identical(_connecting, connected)) _connecting = null;
    }
  }

  void _startWriteCooldown() {
    if (_writeDelay <= Duration.zero) return;
    final ready = Completer<void>();
    _writeReady = ready;
    _writeCooldown = Timer(_writeDelay, ready.complete);
  }

  @override
  Future<void> write(List<int> data) async {
    final generation = _generation;
    final characteristic = _writeCharacteristic;
    if (characteristic == null) throw StateError('Scooter is not connected.');
    // Keep the initial settling period and a full gap after each completed
    // write. Time spent idle already satisfies that gap; do not wait it twice.
    await _writeReady?.future;
    if (generation != _generation) throw StateError('Connection cancelled.');
    try {
      await characteristic
          .write(
            data,
            withResponse: selection!.writeMode == GattWriteMode.withResponse,
          )
          .timeout(const Duration(seconds: 3));
    } finally {
      if (generation == _generation) _startWriteCooldown();
    }
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    final connecting = _connecting;
    _connecting = null;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(StateError('Connection cancelled.'));
    }
    _writeCharacteristic = null;
    _writeDelay = Duration.zero;
    _writeCooldown?.cancel();
    _writeCooldown = null;
    final writeReady = _writeReady;
    _writeReady = null;
    if (writeReady != null && !writeReady.isCompleted) writeReady.complete();
    _mtu = null;
    _mtuNotice = null;
    discoveredServices = const [];
    selection = null;
    final notify = _notifySubscription;
    final connection = _connection;
    _notifySubscription = null;
    _connection = null;
    try {
      await notify?.cancel();
    } finally {
      await connection?.cancel();
    }
  }

  @override
  Future<void> close() async {
    await disconnect();
    await _notifications.close();
    await _disconnected.close();
  }
}
