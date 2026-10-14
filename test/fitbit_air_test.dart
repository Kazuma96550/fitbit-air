import 'package:fitbit_air/fitbit_air.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fitbit_air');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('reports whether a paired Air is present', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
    expect(await FitbitAir.isAirPaired(), isTrue);
  });

  test('returns verified vibration result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'originalIntensity': 2,
            'restored': true,
            'verified': true,
          },
        );
    final result = await FitbitAir.vibrate();
    expect(result.originalIntensity, 2);
    expect(result.restored, isTrue);
    expect(result.verified, isTrue);
  });

  test('returns a verified one-pulse intensity transition', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'previousIntensity': 2,
            'currentIntensity': 3,
            'changed': true,
            'verified': true,
          },
        );
    final result = await FitbitAir.pulse();
    expect(result.previousIntensity, HapticIntensity.low);
    expect(result.currentIntensity, HapticIntensity.high);
    expect(result.changed, isTrue);
    expect(result.verified, isTrue);
  });

  test('maps native errors to a typed exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
            code: 'AIR_NOT_FOUND',
            message: 'Pair the device first.',
          ),
        );
    await expectLater(FitbitAir.vibrate(), throwsA(isA<FitbitAirException>()));
  });
}
