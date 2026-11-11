import 'package:platform_features/platform_features.dart';
import 'package:flutter/services.dart';

enum AppIconPreset { standard, material, midnight, volt }

extension AppIconLabel on AppIconPreset {
  String get label => switch (this) {
    AppIconPreset.standard => 'Original',
    AppIconPreset.material => 'Material 3',
    AppIconPreset.midnight => 'Midnight',
    AppIconPreset.volt => 'Volt',
  };
  int get background => switch (this) {
    AppIconPreset.standard => 0xff2563eb,
    AppIconPreset.material => 0xffeaddff,
    AppIconPreset.midnight => 0xff12151c,
    AppIconPreset.volt => 0xffc3f64b,
  };
  int get foreground => switch (this) {
    AppIconPreset.standard => 0xffffffff,
    AppIconPreset.material => 0xff21005d,
    AppIconPreset.midnight => 0xffe7ecf5,
    AppIconPreset.volt => 0xff172006,
  };
}

class AppIconService {
  static const _channel = MethodChannel(platformFeaturesMethods);
  Future<Map<Object?, Object?>> capabilities() async =>
      Map<Object?, Object?>.from(
        await _channel.invokeMethod<Map>('iconInfo') ?? {},
      );
  Future<void> select(AppIconPreset preset) =>
      _channel.invokeMethod<void>('setIcon', {'name': preset.name});
}
