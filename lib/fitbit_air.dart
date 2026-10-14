import 'package:flutter/services.dart';

/// A small Android bridge for directly controlling a paired Fitbit Air.
///
/// The Air must already be paired to this Android phone in Google Health.
/// This package does not use the retired Fitbit Web API or Google Health cloud
/// APIs. Wrist-tap detection is not yet implemented.
class FitbitAir {
  FitbitAir._();

  static const MethodChannel _channel = MethodChannel('fitbit_air');

  /// Returns whether a Fitbit Air is present in Android's bonded-device list.
  /// Android may prompt for the Nearby devices permission on first use.
  static Future<bool> isAirPaired() async =>
      await _channel.invokeMethod<bool>('isAirPaired') ?? false;

  /// Reads the persistent vibration strength without changing it.
  static Future<HapticIntensity> getHapticIntensity() async {
    final result = await _invokeMap('getHapticIntensity');
    return HapticIntensity.fromWireValue(result['intensity']! as int);
  }

  /// Sets and verifies the persistent vibration strength.
  ///
  /// Changing the value causes one physical pulse on the Air. Requesting the
  /// value already in use is a no-op.
  static Future<HapticChangeResult> setHapticIntensity(
    HapticIntensity intensity,
  ) async => HapticChangeResult.fromMap(
    await _invokeMap('setHapticIntensity', {'intensity': intensity.wireValue}),
  );

  /// Produces one pulse by switching to the other vibration strength.
  ///
  /// The new strength intentionally remains active, so successive calls
  /// normally alternate between low and high. Google Health may independently
  /// reconcile its stored setting later. Use [vibrate] when plugin-controlled
  /// restoration is more important than producing exactly one pulse.
  static Future<HapticChangeResult> pulse() async =>
      HapticChangeResult.fromMap(await _invokeMap('pulse'));

  /// Sends a short, bounded haptic test and restores the previous intensity.
  ///
  /// Requires the Air to be paired with Google Health on this same phone.
  /// Throws [FitbitAirException] when Bluetooth permission, connection,
  /// transport negotiation, or the setting restore/verification fails.
  static Future<VibrationResult> vibrate() async {
    final result = await _invokeMap('vibrate');
    return VibrationResult.fromMap(result);
  }

  static Future<Map<String, Object?>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      if (result == null) {
        throw const FitbitAirException('EMPTY_RESULT', 'No result returned.');
      }
      return result;
    } on PlatformException catch (error) {
      throw FitbitAirException(
        error.code,
        error.message ?? 'Fitbit Air operation failed.',
      );
    }
  }
}

/// Persistent haptic strength supported by the tested Air firmware.
enum HapticIntensity {
  low(2),
  high(3);

  const HapticIntensity(this.wireValue);

  final int wireValue;

  static HapticIntensity fromWireValue(int value) => switch (value) {
    2 => low,
    3 => high,
    _ => throw FitbitAirException(
      'UNSUPPORTED_INTENSITY',
      'Air returned unsupported haptic intensity $value.',
    ),
  };
}

/// Result of a persistent haptic change or a one-pulse toggle.
class HapticChangeResult {
  const HapticChangeResult({
    required this.previousIntensity,
    required this.currentIntensity,
    required this.changed,
    required this.verified,
  });

  final HapticIntensity previousIntensity;
  final HapticIntensity currentIntensity;
  final bool changed;
  final bool verified;

  factory HapticChangeResult.fromMap(Map<String, Object?> map) =>
      HapticChangeResult(
        previousIntensity: HapticIntensity.fromWireValue(
          map['previousIntensity']! as int,
        ),
        currentIntensity: HapticIntensity.fromWireValue(
          map['currentIntensity']! as int,
        ),
        changed: map['changed']! as bool,
        verified: map['verified']! as bool,
      );
}

/// Result of a direct haptic test.
class VibrationResult {
  const VibrationResult({
    required this.originalIntensity,
    required this.restored,
    required this.verified,
  });

  /// The prior intensity: 2 (low) or 3 (high), as reported by the Air.
  final int originalIntensity;

  /// Whether the plugin received an accepted response restoring that setting.
  final bool restored;

  /// Whether a follow-up read confirmed that the original setting was restored.
  final bool verified;

  factory VibrationResult.fromMap(Map<String, Object?> map) => VibrationResult(
    originalIntensity: map['originalIntensity']! as int,
    restored: map['restored']! as bool,
    verified: map['verified']! as bool,
  );
}

/// A device or transport error returned by the native Android implementation.
class FitbitAirException implements Exception {
  const FitbitAirException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'FitbitAirException($code): $message';
}
