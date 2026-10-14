import 'package:fitbit_air/fitbit_air_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('fitbit_air');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null),
  );

  test(
    'battery probe distinguishes denied access from a battery measurement',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
            expect(call.method, 'probeBatteryAccess');
            return {'responseClass': 4, 'detail': 1, 'bodyLength': 0};
          });
      final result = await FitbitAirDiagnostics.probeBatteryAccess();
      expect(result.responseCode, '4.01');
      expect(result.granted, isFalse);
      expect(result.bodyLength, 0);
    },
  );

  test(
    'battery probe formats successful access without interpreting contents',
    () {
      final result = AirBatteryAccessResult.fromMap({
        'responseClass': 2,
        'detail': 5,
        'bodyLength': 42,
        'rawBatteryLevel': 77,
        'rawVoltage': 4000,
        'rawOnCharger': 0,
      });
      expect(result.responseCode, '2.05');
      expect(result.granted, isTrue);
      expect(result.bodyLength, 42);
      expect(result.rawBatteryLevel, 77);
      expect(result.rawVoltage, 4000);
      expect(result.rawOnCharger, 0);
      expect(result.decodeError, isNull);
    },
  );

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
