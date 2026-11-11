String normalizeUuid(String uuid) {
  final value = uuid.toLowerCase();
  return value.length == 4
      ? '0000$value-0000-1000-8000-00805f9b34fb'
      : value.length == 8
      ? '$value-0000-1000-8000-00805f9b34fb'
      : value;
}

class NearbyScooter {
  const NearbyScooter(
    this.id,
    this.name,
    this.rssi, {
    this.serviceUuids = const [],
    this.manufacturerData = const [],
  });
  final String id, name;
  final int rssi;
  final List<String> serviceUuids;
  final List<int> manufacturerData;
}

enum GattWriteMode { automatic, withResponse, withoutResponse }

class GattLayout {
  const GattLayout({
    required this.id,
    required this.service,
    required this.notify,
    this.write,
    this.writeService,
    this.writeMode = GattWriteMode.automatic,
  });
  final String id, service, notify;
  final String? write, writeService;
  final GattWriteMode writeMode;
}

class BleConnectionProfile {
  const BleConnectionProfile({
    required this.layouts,
    this.notificationDelay = Duration.zero,
    this.writeDelay = Duration.zero,
    this.preferredMtu,
    this.requiresResponse = false,
  });
  final List<GattLayout> layouts;
  final Duration notificationDelay;

  /// Initial write settling time and minimum gap after a completed write.
  final Duration writeDelay;
  final int? preferredMtu;
  final bool requiresResponse;
}

class GattCharacteristicInfo {
  const GattCharacteristicInfo(
    this.id, {
    this.notify = false,
    this.writeWithResponse = false,
    this.writeWithoutResponse = false,
  });
  final String id;
  final bool notify, writeWithResponse, writeWithoutResponse;
  bool canWrite(GattWriteMode mode) => switch (mode) {
    GattWriteMode.automatic => writeWithResponse || writeWithoutResponse,
    GattWriteMode.withResponse => writeWithResponse,
    GattWriteMode.withoutResponse => writeWithoutResponse,
  };
}

class GattServiceInfo {
  const GattServiceInfo(this.id, this.characteristics);
  final String id;
  final List<GattCharacteristicInfo> characteristics;
}

class GattSelection {
  const GattSelection(
    this.layoutId,
    this.notifyService,
    this.notify,
    this.writeService,
    this.write, {
    this.writeMode = GattWriteMode.automatic,
  });
  final String layoutId, notifyService, notify, writeService, write;
  final GattWriteMode writeMode;
}

GattSelection? selectGattLayout(
  List<GattServiceInfo> services,
  BleConnectionProfile profile, {
  GattWriteMode preferredWriteMode = GattWriteMode.withoutResponse,
}) {
  GattServiceInfo? service(String id) {
    for (final candidate in services) {
      if (normalizeUuid(candidate.id) == normalizeUuid(id)) return candidate;
    }
    return null;
  }

  for (final layout in profile.layouts) {
    final notifications = service(layout.service);
    final writes = service(layout.writeService ?? layout.service);
    if (notifications == null || writes == null) continue;
    final notify = notifications.characteristics
        .where(
          (c) =>
              normalizeUuid(c.id) == normalizeUuid(layout.notify) && c.notify,
        )
        .firstOrNull;
    if (notify == null) continue;
    final writable = writes.characteristics.where(
      (c) => c.canWrite(layout.writeMode),
    );
    final write = layout.write != null
        ? writable
              .where((c) => normalizeUuid(c.id) == normalizeUuid(layout.write!))
              .firstOrNull
        : writable
                  .where((c) => normalizeUuid(c.id) == normalizeUuid(notify.id))
                  .firstOrNull ??
              writable.firstOrNull;
    if (write != null) {
      return GattSelection(
        layout.id,
        notifications.id,
        notify.id,
        writes.id,
        write.id,
        writeMode: layout.writeMode != GattWriteMode.automatic
            ? layout.writeMode
            : write.canWrite(preferredWriteMode)
            ? preferredWriteMode
            : write.writeWithResponse
            ? GattWriteMode.withResponse
            : GattWriteMode.withoutResponse,
      );
    }
  }
  return null;
}
