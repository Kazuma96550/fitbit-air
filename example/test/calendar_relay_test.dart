import 'package:fitbit_air_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const calendar = MethodChannel('fitbit_air_example/calendar');
  const device = MethodChannel('fitbit_air');
  var access = false;
  var running = false;
  var paired = true;
  late List<String> calls;

  setUp(() {
    access = false;
    running = false;
    paired = true;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(calendar, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'status':
              return {
                'access': access,
                'connected': access,
                'running': running,
                'stopping': false,
              };
            case 'start':
              running = true;
              return null;
            case 'stop':
              running = false;
              return null;
            case 'settings':
              return null;
          }
          throw MissingPluginException();
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (call) async {
          calls.add(call.method);
          if (call.method == 'isAirPaired') return paired;
          throw MissingPluginException();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(calendar, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null);
  });

  testWidgets('requires notification access and opens Android setup', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start calendar relay'),
    );
    expect(start.onPressed, isNull);
    await tester.ensureVisible(find.text('Open notification access settings'));
    await tester.tap(find.text('Open notification access settings'));
    await tester.pumpAndSettle();
    expect(calls, contains('settings'));
    expect(calls, isNot(contains('start')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not start without a paired Air', (tester) async {
    access = true;
    paired = false;
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    await tester.ensureVisible(find.text('Start calendar relay'));
    await tester.tap(find.text('Start calendar relay'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('start')));
    expect(find.text('Pair an Air in Google Health first.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refreshes access after returning from settings', (tester) async {
    access = true;
    running = true;
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    expect(find.text('Relay: on'), findsOneWidget);
    access = false;
    running = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Relay: off'), findsOneWidget);
    expect(find.text('Notification access: not enabled'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start calendar relay'),
    );
    expect(start.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starts after pairing check, blocks device controls, and stops', (
    tester,
  ) async {
    access = true;
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    await tester.ensureVisible(find.text('Start calendar relay'));
    await tester.tap(find.text('Start calendar relay'));
    await tester.pumpAndSettle();
    expect(calls.indexOf('isAirPaired'), lessThan(calls.indexOf('start')));
    expect(find.text('Relay: on'), findsOneWidget);
    final pulse = find.text('Single pulse (alternates strength)');
    await tester.scrollUntilVisible(pulse, 400);
    final pulseButton = tester.widget<FilledButton>(
      find
          .ancestor(
            of: pulse,
            matching: find.byWidgetPredicate(
              (widget) => widget is FilledButton,
            ),
          )
          .first,
    );
    expect(pulseButton.onPressed, isNull);
    await tester.scrollUntilVisible(find.text('Stop calendar relay'), -400);
    await tester.tap(find.text('Stop calendar relay'));
    await tester.pumpAndSettle();
    expect(running, isFalse);
    expect(find.text('Relay: off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
