import 'package:flutter/services.dart';

import 'fitbit_air.dart';

/// Research tools whose events do not have a confirmed user-facing meaning.
class FitbitAirDiagnostics {
  FitbitAirDiagnostics._();

  static const _channel = EventChannel('fitbit_air/device_events');
  static const _methods = MethodChannel('fitbit_air');
  static const _secureChannel = EventChannel('fitbit_air/secure_events');

  /// Observes device-originated POST /events for up to 30 seconds after ready.
  /// Opens a bootstrap DTLS session and ACKs valid event messages, but sends no
  /// setting, alarm, sync or reset command. May contend with Google Health.
  /// These are protocol events, NOT confirmed wrist taps. The 45-second total
  /// operation deadline can end the capture early if negotiation is slow.
  static Stream<AirSecureEvent> watchSecureEvents() => _secureChannel
      .receiveBroadcastStream()
      .map(
        (value) =>
            AirSecureEvent.fromMap(Map<String, Object?>.from(value as Map)),
      )
      .handleError((Object error) {
        if (error is PlatformException) {
          throw FitbitAirException(
            error.code,
            error.message ?? 'Secure event capture failed.',
          );
        }
        throw error;
      });

  /// One secure session, four fixed source-traced GET requests. Never writes
  /// settings or returns raw bodies, alarm times, or activity measurements.
  /// This is research tooling, not a promise of access or sync coexistence.
  static Future<List<AirResourceAccessResult>> probeReadOnlyResources() async {
    try {
      final value = await _methods.invokeMapMethod<String, Object?>(
        'probeReadOnlyResources',
      );
      if (value == null) {
        throw const FitbitAirException(
          'EMPTY_RESPONSE',
          'Resource probe returned no result.',
        );
      }
      return List.unmodifiable(
        (value['resources']! as List).map(
          (entry) => AirResourceAccessResult.fromMap(
            Map<String, Object?>.from(entry as Map),
          ),
        ),
      );
    } on PlatformException catch (error) {
      throw FitbitAirException(
        error.code,
        error.message ?? 'Resource probe failed.',
      );
    }
  }

  /// Research-only GET of the device-info resource that includes battery data.
  /// Opens a Golden Gate session, so Google Health coexistence is NOT assured.
  /// Sends no setting writes. Returns response status and selected raw battery
  /// fields, never identifiers or the original body. Units are unverified;
  /// rawBatteryLevel must not be assumed to be a percentage.
  static Future<AirBatteryAccessResult> probeBatteryAccess() async {
    try {
      final value = await _methods.invokeMapMethod<String, Object?>(
        'probeBatteryAccess',
      );
      if (value == null) {
        throw const FitbitAirException(
          'EMPTY_RESPONSE',
          'Battery probe returned no result.',
        );
      }
      return AirBatteryAccessResult.fromMap(value);
    } on PlatformException catch (error) {
      throw FitbitAirException(
        error.code,
        error.message ?? 'Battery probe failed.',
      );
    }
  }

  /// Watches notification characteristics in the Air's link-status and
  /// unclassified services. Excludes the Goldengate tracker channel and HR.
  ///
  /// These are **not confirmed tap events**. Payloads may contain sensitive
  /// device data; keep them local unless the user explicitly chooses to share.
  /// Cancel the subscription before another SDK operation.
  static Stream<AirDeviceEvent> watchDeviceEvents() => _channel
      .receiveBroadcastStream()
      .map(
        (value) =>
            AirDeviceEvent.fromMap(Map<String, Object?>.from(value as Map)),
      )
      .handleError((Object error) {
        if (error is PlatformException) {
          throw FitbitAirException(
            error.code,
            error.message ?? 'Device event monitor failed.',
          );
        }
        throw error;
      });
}

/// Bounded CoAP event metadata; unknown IDs are not interpreted as gestures.
class AirSecureEvent {
  AirSecureEvent.fromMap(Map<String, Object?> map)
    : kind = map['kind']! as String,
      receivedAt = DateTime.fromMillisecondsSinceEpoch(
        map['receivedAtMillis']! as int,
      ),
      eventIds = List.unmodifiable(
        (map['eventIds'] as List? ?? []).cast<int>(),
      ),
      eventNames = List.unmodifiable(
        (map['eventNames'] as List? ?? []).cast<String>(),
      ),
      receivedPosts = map['receivedPosts'] as int?,
      droppedPosts = map['droppedPosts'] as int?,
      durationSeconds = map['durationSeconds'] as int?;
  final String kind;
  final DateTime receivedAt;
  final List<int> eventIds;
  final List<String> eventNames;
  final int? receivedPosts;
  final int? droppedPosts;
  final int? durationSeconds;
}

/// Access metadata only; a successful response is not a decoded stats API.
class AirResourceAccessResult {
  AirResourceAccessResult.fromMap(Map<String, Object?> map)
    : path = map['path']! as String,
      responseClass = map['responseClass'] as int?,
      detail = map['detail'] as int?,
      bodyLength = map['bodyLength'] as int?,
      errorCode = map['errorCode'] as String?;
  final String path;
  final int? responseClass;
  final int? detail;
  final int? bodyLength;
  final String? errorCode;
  bool get granted => responseClass == 2;
  String? get responseCode => responseClass == null || detail == null
      ? null
      : '$responseClass.${detail.toString().padLeft(2, '0')}';
}

/// Access status and selected battery fields with unverified scale/units.
class AirBatteryAccessResult {
  AirBatteryAccessResult.fromMap(Map<String, Object?> map)
    : responseClass = map['responseClass']! as int,
      detail = map['detail']! as int,
      bodyLength = map['bodyLength']! as int,
      rawBatteryLevel = map['rawBatteryLevel'] as int?,
      rawVoltage = map['rawVoltage'] as int?,
      rawOnCharger = map['rawOnCharger'] as int?,
      decodeError = map['decodeError'] as String?;
  final int responseClass;
  final int detail;
  final int bodyLength;
  final int? rawBatteryLevel;
  final int? rawVoltage;
  final int? rawOnCharger;
  final String? decodeError;
  bool get granted => responseClass == 2;
  String get responseCode =>
      '$responseClass.${detail.toString().padLeft(2, '0')}';
}

/// A subscription result, monitor readiness message, or unclassified BLE value.
class AirDeviceEvent {
  AirDeviceEvent.fromMap(Map<String, Object?> map)
    : kind = map['kind']! as String,
      receivedAt = DateTime.fromMillisecondsSinceEpoch(
        map['receivedAtMillis']! as int,
      ),
      serviceUuid = map['serviceUuid'] as String?,
      characteristicUuid = map['characteristicUuid'] as String?,
      status = map['status'] as int?,
      subscribedCount = map['subscribed'] as int?,
      payload = Uint8List.fromList(
        (map['payload'] as Uint8List?) ?? Uint8List(0),
      );

  final String kind;
  final DateTime receivedAt;
  final String? serviceUuid;
  final String? characteristicUuid;
  final int? status;
  final int? subscribedCount;
  final Uint8List payload;

  bool get isNotification => kind == 'notification';
}
