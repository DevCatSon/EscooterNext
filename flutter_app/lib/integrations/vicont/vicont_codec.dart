import 'dart:typed_data';

import '../../core/hex_bytes.dart';
import '../../core/display_units.dart';

/// Vicont framing and conversions; selectable ranges are app policy.
/// Source evidence and wire reference: docs/ble/VICONT.md at the repository root.
abstract final class Protocol {
  static const lock = 51;
  static const find = 52;
  static const kickStart = 53;
  static const cruise = 54;
  static const maxSpeed = 60;
  static const startTorque = 61;
  static const maxTorque = 62;
  static const brake = 63;
  static const ambient = 65;
  static const gear = 66;
  static const unit = 67;
  static const headlight = 69;
  static const workMode = 74;
  static const version = 171;
  static const query = 0;
  static const reset = 255;
  static const minSpeedKmh = 1;
  static const maxSpeedKmh = 31;
  static const milesPerKm = 0.6213712;
  static const prefixes = ['E-S', 'VC_', 'VC-', 'SN', 'VA-', 'ZL'];

  static final handshake = [
    fromHex('FAAFA55A01005B'),
    fromHex('FAAFA5FA01005B'),
  ];

  static Uint8List command(int zt, int code, List<int> data) {
    if (code < 0 ||
        code > 255 ||
        data.length > 255 ||
        data.any((value) => value < 0 || value > 255)) {
      throw ArgumentError('Commands and payload values must fit in one byte.');
    }
    final body = [zt & 255, code, data.length, ...data];
    return Uint8List.fromList([
      0xfa,
      0xaf,
      0xa5,
      ...body,
      body.fold(0, (a, b) => a + b) & 255,
    ]);
  }

  static int switchByte(bool currentlyOn) => currentlyOn ? 1 : 2;
  static int speedByte(int kmh) => kmh.clamp(minSpeedKmh, maxSpeedKmh);
  static int torqueByte(int level) => level.clamp(1, 10) * 20;
  static int brakeByte(int level) =>
      level.clamp(0, 9) == 0 ? 1 : (level.clamp(0, 9) / 9 * 200).floor();
  static int torqueLevel(int raw, int? maximum, {bool starting = false}) =>
      _scale(raw, maximum, starting ? 99 : 25, 10, 1, 10);
  static int brakeLevel(int raw, int? maximum) =>
      _scale(raw, maximum, 99, 9, 0, 9);
  static int _scale(
    int raw,
    int? max,
    int fallback,
    int span,
    int low,
    int high,
  ) => (raw / (max != null && max > 0 ? max : fallback) * span).round().clamp(
    low,
    high,
  );
  static int? displayGear(int? raw) => switch (raw) {
    1 => 1,
    2 => 2,
    3 || 4 || 5 => 3,
    _ => null,
  };
  static double displayDistance(num km, bool miles) =>
      DisplayUnits.distance(km, miles);
  static String hex(Iterable<int> bytes) => HexBytes.format(bytes);
  static Uint8List fromHex(String text) =>
      Uint8List.fromList(HexBytes.parse(text));
}

class IncomingFrame {
  const IncomingFrame(this.zt, this.code, this.data, this.checksumOk);
  final int zt;
  final int code;
  final List<int> data;
  final bool checksumOk;
}

/// Reassembles split packets without letting a damaged length poison the stream.
class NotificationFramer {
  final List<int> _buffer = [];
  int discardedBytes = 0;
  bool _possibleTrailer = false;

  // RX has no magic prefix. Recovery therefore needs both a known opcode and
  // a complete checksum-valid candidate, rather than trusting an arbitrary LEN.
  static const _recoveryCodes = {
    1,
    16,
    17,
    18,
    19,
    20,
    31,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    60,
    61,
    62,
    63,
    65,
    66,
    67,
    69,
    71,
    74,
    75,
    76,
    161,
    162,
    163,
    171,
    172,
  };

  static bool _verified(List<int> bytes, int start) {
    if (bytes.length - start < 4) return false;
    final end = start + 4 + bytes[start + 2];
    if (end > bytes.length) return false;
    var sum = 0;
    for (var i = start; i < end - 1; i++) {
      sum += bytes[i];
    }
    return (sum & 255) == bytes[end - 1];
  }

  List<IncomingFrame> add(List<int> bytes) {
    discardedBytes = 0;
    if (bytes.isEmpty) return const [];
    final combined = [..._buffer, ...bytes];
    // Prefer a verified reassembly. Otherwise, a complete packet at the next
    // notification boundary supersedes an abandoned fragment, as in the stock
    // client's notification-based receive path (docs/ble/VICONT.md).
    if (_buffer.isNotEmpty &&
        !_verified(combined, 0) &&
        bytes.length >= 4 &&
        _recoveryCodes.contains(bytes[1]) &&
        _verified(bytes, 0)) {
      // The captured G30 reports append 00 after the valid checksum. Hold that
      // byte until the next packet proves it is a trailer rather than ZT=0.
      if (!_possibleTrailer) discardedBytes += _buffer.length;
      _buffer.clear();
    }
    _possibleTrailer = false;
    _buffer.addAll(bytes);
    final frames = <IncomingFrame>[];
    var cursor = 0;
    while (_buffer.length - cursor >= 4) {
      final length = _buffer[cursor + 2];
      final end = cursor + 4 + length;
      final valid = _verified(_buffer, cursor);
      // Do not search inside a plausible, still-incomplete packet: sensor data
      // can coincidentally contain an entire frame-shaped byte sequence.
      if (!valid &&
          (end <= _buffer.length ||
              !_recoveryCodes.contains(_buffer[cursor + 1]))) {
        var next = cursor + 1;
        while (next + 4 <= _buffer.length &&
            !(_recoveryCodes.contains(_buffer[next + 1]) &&
                _verified(_buffer, next))) {
          next++;
        }
        if (next + 4 <= _buffer.length) {
          final trailer =
              next == cursor + 1 &&
              _buffer[cursor] == 0 &&
              frames.isNotEmpty &&
              frames.last.checksumOk;
          if (!trailer) discardedBytes += next - cursor;
          cursor = next;
          continue;
        }
      }
      if (_buffer.length < end) break;
      frames.add(
        IncomingFrame(
          _buffer[cursor],
          _buffer[cursor + 1],
          List.unmodifiable(_buffer.sublist(cursor + 3, end - 1)),
          valid,
        ),
      );
      cursor = end;
    }
    if (cursor > 0) _buffer.removeRange(0, cursor);
    _possibleTrailer =
        _buffer.length == 1 &&
        _buffer.single == 0 &&
        frames.isNotEmpty &&
        frames.last.checksumOk;
    return frames;
  }

  void clear() {
    _buffer.clear();
    discardedBytes = 0;
    _possibleTrailer = false;
  }
}
