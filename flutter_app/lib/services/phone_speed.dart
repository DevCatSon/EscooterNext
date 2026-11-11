import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_features/platform_features.dart';

enum SpeedSource { scooter, phone, mixed }

extension SpeedSourceLabel on SpeedSource {
  String get label => switch (this) {
    SpeedSource.scooter => 'Scooter reported speed',
    SpeedSource.phone => 'Phone reported speed',
    SpeedSource.mixed => 'Mixed',
  };
}

class PhoneSpeedSample {
  const PhoneSpeedSample({
    required this.metersPerSecond,
    required this.horizontalAccuracy,
    required this.age,
    required this.receivedAt,
    this.speedAccuracy,
  });
  final double metersPerSecond, horizontalAccuracy;
  final double? speedAccuracy;
  final Duration age;
  final DateTime receivedAt;
  bool usable(DateTime now) {
    final elapsed = now.difference(receivedAt);
    if (elapsed.isNegative ||
        age.isNegative ||
        age + elapsed > const Duration(seconds: 3)) {
      return false;
    }
    return metersPerSecond.isFinite &&
        metersPerSecond >= 0 &&
        horizontalAccuracy.isFinite &&
        horizontalAccuracy >= 0 &&
        horizontalAccuracy <= 25 &&
        (speedAccuracy == null
            ? horizontalAccuracy <= 15
            : speedAccuracy!.isFinite &&
                  speedAccuracy! >= 0 &&
                  speedAccuracy! <= 1.5);
  }

  double get kmh => metersPerSecond * 3.6;
}

abstract interface class PhoneSpeedProvider {
  Future<void> authorize();
  Stream<PhoneSpeedSample> get samples;
}

class NativePhoneSpeedProvider implements PhoneSpeedProvider {
  static const _methods = MethodChannel(platformFeaturesMethods);
  static const _events = EventChannel(platformFeaturesSpeed);
  @override
  Future<void> authorize() => _methods.invokeMethod<void>('authorizeLocation');
  @override
  Stream<PhoneSpeedSample> get samples =>
      _events.receiveBroadcastStream().map((event) {
        final data = Map<Object?, Object?>.from(event as Map);
        return PhoneSpeedSample(
          metersPerSecond: (data['speed'] as num?)?.toDouble() ?? -1,
          horizontalAccuracy: (data['accuracy'] as num?)?.toDouble() ?? -1,
          speedAccuracy: (data['speedAccuracy'] as num?)?.toDouble(),
          age: Duration(milliseconds: (data['ageMs'] as num?)?.toInt() ?? -1),
          receivedAt: DateTime.now(),
        );
      });
}

class SpeedEstimate {
  const SpeedEstimate(this.kmh, this.origin);
  final double? kmh;
  final String origin;
}

/// Mixed is an estimate, not a calibrated instrument. See docs/PERSONALIZATION.md.
SpeedEstimate estimateSpeed(
  SpeedSource source,
  double? scooter,
  PhoneSpeedSample? phone,
) {
  if (source == SpeedSource.scooter) return SpeedEstimate(scooter, 'Scooter');
  if (source == SpeedSource.phone) {
    return SpeedEstimate(
      phone?.kmh,
      phone == null ? 'Waiting for phone speed' : 'Phone GPS',
    );
  }
  if (phone == null) {
    return SpeedEstimate(
      scooter,
      scooter == null ? 'Waiting for speed' : 'Scooter · GPS unavailable',
    );
  }
  if (scooter == null) {
    return SpeedEstimate(phone.kmh, 'Phone GPS · scooter unavailable');
  }
  // Wheel speed has no reported uncertainty. This conservative application
  // assumption must not be confused with a measured sensor accuracy.
  final wheelSigma = math.max(1.0, scooter * .05);
  final gpsSigma = math.max(.5, (phone.speedAccuracy ?? 1.5) * 3.6);
  if ((scooter - phone.kmh).abs() >
      math.max(
        8,
        3 * math.sqrt(wheelSigma * wheelSigma + gpsSigma * gpsSigma),
      )) {
    return SpeedEstimate(phone.kmh, 'Phone GPS · readings disagree');
  }
  final phoneWeight =
      (wheelSigma *
              wheelSigma /
              (wheelSigma * wheelSigma + gpsSigma * gpsSigma))
          .clamp(.25, .85);
  return SpeedEstimate(
    phone.kmh * phoneWeight + scooter * (1 - phoneWeight),
    'Phone + scooter',
  );
}

class PhoneSpeedMonitor extends ChangeNotifier {
  PhoneSpeedMonitor(this.provider, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final PhoneSpeedProvider provider;
  final DateTime Function() now;
  StreamSubscription<PhoneSpeedSample>? _subscription;
  Timer? _expiry;
  PhoneSpeedSample? _sample;
  String? status;
  int _generation = 0;
  PhoneSpeedSample? get sample =>
      _sample?.usable(now()) == true ? _sample : null;
  void setEnabled(bool enabled) {
    if (enabled == (_subscription != null)) return;
    final generation = ++_generation;
    _expiry?.cancel();
    _sample = null;
    status = enabled ? 'Waiting for accurate phone speed' : null;
    final old = _subscription;
    _subscription = null;
    unawaited(old?.cancel());
    if (!enabled) return;
    _subscription = provider.samples.listen(
      (value) {
        if (generation != _generation) return;
        _expiry?.cancel();
        _sample = value.usable(now()) ? value : null;
        status = _sample == null ? 'Waiting for accurate phone speed' : null;
        if (_sample != null) {
          final remaining =
              const Duration(seconds: 3) -
              value.age -
              now().difference(value.receivedAt);
          _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
            if (generation != _generation) return;
            _sample = null;
            status = 'Phone speed is stale';
            notifyListeners();
          });
        }
        notifyListeners();
      },
      onError: (Object error) {
        if (generation != _generation) return;
        _expiry?.cancel();
        _sample = null;
        status = error is PlatformException
            ? error.message ?? 'Phone speed unavailable'
            : 'Phone speed unavailable';
        notifyListeners();
      },
      onDone: () {
        if (generation != _generation) return;
        _expiry?.cancel();
        _subscription = null;
        _sample = null;
        status = 'Phone speed stopped';
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    ++_generation;
    _expiry?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
