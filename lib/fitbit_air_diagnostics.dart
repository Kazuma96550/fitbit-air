import 'package:flutter/services.dart';

import 'fitbit_air.dart';

/// Research tools whose events do not have a confirmed user-facing meaning.
class FitbitAirDiagnostics {
  FitbitAirDiagnostics._();

  static const _channel = EventChannel('fitbit_air/device_events');

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
