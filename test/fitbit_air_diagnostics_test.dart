import 'package:fitbit_air/fitbit_air_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notification copies the codec payload without interpreting it as a tap',
    () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final event = AirDeviceEvent.fromMap({
        'kind': 'notification',
        'receivedAtMillis': 1234,
        'serviceUuid': 'service',
        'characteristicUuid': 'characteristic',
        'payload': bytes,
      });
      bytes[0] = 99;
      expect(event.payload, [1, 2, 3]);
      expect(event.isNotification, isTrue);
      expect(event.receivedAt.millisecondsSinceEpoch, 1234);
      expect(event.characteristicUuid, 'characteristic');
    },
  );

  test('control events have no measurement payload', () {
    final ready = AirDeviceEvent.fromMap({
      'kind': 'ready',
      'receivedAtMillis': 1000,
      'subscribed': 7,
    });
    expect(ready.subscribedCount, 7);
    expect(ready.payload, isEmpty);
    expect(ready.isNotification, isFalse);
    final disconnected = AirDeviceEvent.fromMap({
      'kind': 'disconnected',
      'receivedAtMillis': 2000,
      'status': 257,
    });
    expect(disconnected.status, 257);
    expect(disconnected.isNotification, isFalse);
  });
}
