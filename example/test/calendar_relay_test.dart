import 'package:fitbit_air_example/demo/demo_controller.dart';
import 'package:fitbit_air_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = DemoController.channel;
  const device = MethodChannel('fitbit_air');
  var access = false;
  var running = false;
  var paired = true;
  var deferStop = false;
  late List<Map<String, Object?>> history;
  late List<String> calls;
  late List<String> selected;
  late DemoController controller;

  setUp(() {
    access = false;
    running = false;
    paired = true;
    deferStop = false;
    history = [];
    calls = [];
    selected = ['com.google.android.calendar'];
    controller = DemoController();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'status':
              return {
                'access': access,
                'connected': access,
                'running': running,
                'ready': running,
                'stopping': false,
                'selectedApps': selected,
                'bluetoothEnabled': true,
                'bluetoothPermission': true,
                'history': history,
              };
            case 'apps':
              return [
                {
                  'packageName': 'com.google.android.calendar',
                  'label': 'Google Calendar',
                },
                {'packageName': 'com.whatsapp', 'label': 'WhatsApp'},
                {
                  'packageName': 'org.thoughtcrime.securesms',
                  'label': 'Signal',
                },
              ];
            case 'selectApps':
              selected = List<String>.from(
                (call.arguments as Map)['packages'] as List,
              );
              return null;
            case 'labSettings':
              return {'secureDurationSeconds': 60};
            case 'setLabSettings':
              return null;
            case 'start':
              running = true;
              return null;
            case 'stop':
              if (!deferStop) running = false;
              return null;
            case 'settings':
            case 'bluetoothSettings':
            case 'clearHistory':
            case 'testPulse':
              return null;
          }
          throw MissingPluginException();
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (call) async {
          calls.add(call.method);
          if (call.method == 'isAirPaired') return paired;
          if (call.method == 'pulse') {
            return {
              'previousIntensity': 2,
              'currentIntensity': 3,
              'changed': true,
              'verified': true,
            };
          }
          if (call.method == 'vibrate') {
            return {'originalIntensity': 2, 'restored': true, 'verified': true};
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(DemoApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('requires notification access and keeps setup actionable', (
    tester,
  ) async {
    await mount(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('relay-toggle')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(calls, contains('settings'));
    expect(calls, isNot(contains('start')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not start without a paired Air', (tester) async {
    access = true;
    paired = false;
    await mount(tester);
    await tap(tester, 'relay-toggle');
    expect(calls, isNot(contains('start')));
    expect(controller.setupError, contains('Pair the Air'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refreshes access after returning from settings', (tester) async {
    access = true;
    running = true;
    await mount(tester);
    expect(controller.relayRunning, isTrue);
    access = false;
    running = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.relayRunning, isFalse);
    expect(find.text('Notification access: not enabled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching to Lab never silently stops the relay', (
    tester,
  ) async {
    access = true;
    running = true;
    await mount(tester);
    await tap(tester, 'nav-lab');
    expect(controller.secureDurationSeconds, 60);
    expect(find.byKey(const ValueKey('secure-duration')), findsOneWidget);
    expect(calls, isNot(contains('stop')));
    expect(controller.relayRunning, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('exclusive actions require an explicit relay stop', (
    tester,
  ) async {
    access = true;
    running = true;
    await mount(tester);
    await tap(tester, 'nav-device');
    await tap(tester, 'action-pulse');
    expect(find.byKey(const ValueKey('keep-relay')), findsOneWidget);
    expect(calls, isNot(contains('pulse')));
    await tap(tester, 'keep-relay');
    expect(running, isTrue);
    await tap(tester, 'action-pulse');
    await tap(tester, 'stop-relay-for-operation');
    expect(calls.indexOf('stop'), lessThan(calls.indexOf('pulse')));
    expect(controller.trials.first['outcome'], 'completed');
    expect(running, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app picker supports search and saved selections', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'app-picker');
    await tester.ensureVisible(find.byKey(const ValueKey('app-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('app-search')), 'whats');
    await tester.pumpAndSettle();
    expect(controller.filteredApps.single['packageName'], 'com.whatsapp');
    await tap(tester, 'app-com.whatsapp');
    expect(
      selected,
      containsAll(['com.google.android.calendar', 'com.whatsapp']),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('requires a nonempty allowlist before starting', (tester) async {
    access = true;
    selected = [];
    await mount(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('relay-toggle')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'relay test uses the running worker rather than another connection',
    (tester) async {
      access = true;
      running = true;
      await mount(tester);
      await tap(tester, 'test-vibration');
      expect(calls, contains('testPulse'));
      expect(calls, isNot(contains('vibrate')));
      expect(running, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'device controls use the same named actions as the test harness',
    (tester) async {
      await mount(tester);
      await controller.runAction('preview');
      expect(calls.where((value) => value == 'vibrate'), hasLength(1));
      expect(controller.trials.single['operation'], 'preview');
      expect(controller.trials.single['outcome'], 'completed');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('exclusive operation waits for in-flight relay cleanup', (
    tester,
  ) async {
    access = true;
    running = true;
    deferStop = true;
    await mount(tester);
    await tap(tester, 'nav-device');
    await tap(tester, 'action-pulse');
    await tap(tester, 'stop-relay-for-operation');
    expect(calls, contains('stop'));
    expect(calls, isNot(contains('pulse')));
    running = false;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(calls, contains('pulse'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history distinguishes verification and uncertain failure', (
    tester,
  ) async {
    history = [
      {
        'commandId': 'one',
        'sourcePackage': 'com.whatsapp',
        'stage': 'verified',
        'atMillis': 1000,
        'latencyMillis': 125,
      },
      {
        'commandId': 'two',
        'sourcePackage': 'com.whatsapp',
        'stage': 'failed',
        'atMillis': 2000,
        'errorCode': 'TIMEOUT',
      },
    ];
    await mount(tester);
    final target = find.byKey(const ValueKey('activity-one-verified'));
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp · Command verified'), findsOneWidget);
    expect(controller.history, hasLength(2));
    expect(controller.exportJson(), contains('TIMEOUT'));
    expect(find.textContaining('delivery is uncertain'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
