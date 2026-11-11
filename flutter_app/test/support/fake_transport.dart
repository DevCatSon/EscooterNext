import 'dart:async';

import 'package:escooter_control/services/ble_transport.dart';

List<int> incoming(int code, List<int> data, {int zt = 0x5a}) {
  final body = [zt, code, data.length, ...data];
  return [...body, body.fold(0, (a, b) => a + b) & 255];
}

class FakeTransport implements ScooterTransport {
  final received = StreamController<List<int>>.broadcast(sync: true);
  final links = StreamController<void>.broadcast(sync: true);
  final advertisements = StreamController<NearbyScooter>.broadcast(sync: true);
  final writes = <List<int>>[];
  @override
  List<GattServiceInfo> discoveredServices = const [
    GattServiceInfo('fee0', [
      GattCharacteristicInfo('fee2', notify: true, writeWithoutResponse: true),
    ]),
  ];
  @override
  GattSelection? selection = const GattSelection(
    'fee0-fee2',
    'fee0',
    'fee2',
    'fee0',
    'fee2',
  );
  BleConnectionProfile? lastProfile;
  int prepares = 0;
  int connections = 0;
  bool replyToHandshake = true;
  bool replyToConfig = true;
  @override
  Map<String, Object?> get diagnostics => const {'platform': 'test'};
  void Function(List<int>)? onWrite;
  @override
  Stream<List<int>> get notifications => received.stream;
  @override
  Stream<void> get disconnected => links.stream;
  @override
  Future<void> prepare() async {
    prepares++;
  }

  @override
  Stream<NearbyScooter> scan() => advertisements.stream;
  @override
  Future<void> connect(
    String id, {
    required BleConnectionProfile profile,
  }) async {
    connections++;
    lastProfile = profile;
  }

  @override
  Future<void> write(List<int> data) async {
    writes.add(List.of(data));
    if (data.length >= 7) {
      final code = data[4];
      if (replyToHandshake && code == 1 && data[3] == 0xfa) {
        received.add(const [0x5a, 1, 0, 0x5b]);
      }
      if (code == 171) received.add(incoming(171, [2, 31]));
      if (replyToConfig && code >= 60 && code <= 63) {
        final value = data[6] == 0 || data[6] == 255
            ? switch (code) {
                60 => 25,
                61 => 100,
                62 => 140,
                _ => 88,
              }
            : data[6];
        received.add(incoming(code, [value, 200]));
      }
    }
    onWrite?.call(data);
  }

  void emit(int code, List<int> data) => received.add(incoming(code, data));
  void status({int flags = 3, int second = 1}) =>
      emit(17, [flags, second, 0x01, 0xd6, 0x05, 0x04, 0, 0, 0, 0]);
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> close() async {
    await received.close();
    await links.close();
    await advertisements.close();
  }
}
