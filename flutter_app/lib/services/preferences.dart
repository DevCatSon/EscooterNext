import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

export '../models/scooter_control.dart' show Feature;

enum AppAppearance { system, light, dark }

enum AppThemePreset { ocean, mint, sunset, violet, graphite, custom }

extension AppThemeDetails on AppThemePreset {
  String get label => switch (this) {
    AppThemePreset.ocean => 'Ocean',
    AppThemePreset.mint => 'Mint',
    AppThemePreset.sunset => 'Sunset',
    AppThemePreset.violet => 'Violet',
    AppThemePreset.graphite => 'Graphite',
    AppThemePreset.custom => 'Custom',
  };
  int get color => switch (this) {
    AppThemePreset.ocean => 0xff2563eb,
    AppThemePreset.mint => 0xff00876c,
    AppThemePreset.sunset => 0xffb84e16,
    AppThemePreset.violet => 0xff7752bc,
    AppThemePreset.graphite => 0xff62656b,
    AppThemePreset.custom => 0xff2563eb,
  };
}

abstract interface class PreferenceStore {
  String? read(String key);
  Future<void> write(String key, String? value);
}

class LocalPreferenceStore implements PreferenceStore {
  LocalPreferenceStore(this._prefs);
  final SharedPreferences _prefs;
  @override
  String? read(String key) => _prefs.getString(key);
  @override
  Future<void> write(String key, String? value) async {
    final success = value == null
        ? await _prefs.remove(key)
        : await _prefs.setString(key, value);
    if (!success) throw StateError('Could not save this preference.');
  }
}

class MemoryPreferenceStore implements PreferenceStore {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class SavedScooter {
  const SavedScooter(
    this.id,
    this.name, {
    this.advertisedName,
    this.protocolId,
    this.profileId,
  });
  final String id;
  final String name;
  final String? advertisedName, protocolId, profileId;
  String encode() => jsonEncode({
    'id': id,
    'name': name,
    'advertisedName': advertisedName,
    'protocolId': protocolId,
    'profileId': profileId,
  });
  static SavedScooter? decode(String? json) {
    try {
      final map = jsonDecode(json ?? '') as Map<String, dynamic>;
      return SavedScooter(
        map['id'] as String,
        map['name'] as String,
        advertisedName: map['advertisedName'] as String?,
        protocolId: map['protocolId'] as String?,
        profileId: map['profileId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
