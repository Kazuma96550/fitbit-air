import 'package:fitbit_air_example/demo/demo_controller.dart';
import 'package:fitbit_air_example/demo/relay_settings.dart';
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
  var nameCandidate = false;
  var pulseStyle = 'single';
  Map<Object?, Object?>? lastSelection;
  Object? lastTapArguments;
  late List<Map<String, Object?>> history;
  late List<String> calls;
  late List<String> selected;
  late DemoController controller;
  late Map<String, Object?> conversations;
  late Map<String, Object?> rules;

  setUp(() {
    access = false;
    running = false;
    paired = true;
    deferStop = false;
    nameCandidate = false;
    pulseStyle = 'single';
    rules = {
      'defaultPreset': 'single',
      'apps': <String, Object?>{},
      'chats': <String, Object?>{},
      'pauseUntil': 0,
      'quietEnabled': false,
      'startMinute': 1320,
      'endMinute': 420,
    };
    lastSelection = null;
    lastTapArguments = null;
    conversations = {
      'restricted': false,
      'captureRemainingMillis': 0,
      'unsupported': 0,
      'allowed': <Map<String, Object?>>[],
      'candidates': <Map<String, Object?>>[],
    };
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
                'pulseStyle': pulseStyle,
                'rules': {...rules, 'defaultPreset': pulseStyle},
                'bluetoothEnabled': true,
                'bluetoothPermission': true,
                'history': history,
                'conversations': conversations,
              };
            case 'restrictConversations':
              conversations['restricted'] = (call.arguments as Map)['enabled'];
              return null;
            case 'captureConversations':
              conversations['captureRemainingMillis'] =
                  (call.arguments as Map)['enabled'] == true ? 60000 : 0;
              conversations['candidates'] = [
                {
                  'id': 'abcdef012345',
                  'label': 'Private Alice',
                  'packageName': 'com.whatsapp',
                  'kind': nameCandidate ? 'name' : 'shortcut',
                },
              ];
              return null;
            case 'selectConversation':
              lastSelection = Map<Object?, Object?>.from(call.arguments as Map);
              conversations['allowed'] = conversations['candidates'];
              return null;
            case 'clearConversations':
              conversations['allowed'] = <Map<String, Object?>>[];
              conversations['candidates'] = <Map<String, Object?>>[];
              return null;
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
            case 'saveAppRule':
              final args = call.arguments as Map;
              final pkg = args['packageName'] as String;
              (rules['apps'] as Map)[pkg] = {
                'enabled': args['enabled'],
                'preset': args['preset'],
              };
              if (args['enabled'] == true) {
                selected = {...selected, pkg}.toList();
              } else {
                selected.remove(pkg);
              }
              return null;
            case 'saveChatRule':
              final args = call.arguments as Map;
              if (args['preset'] == null) {
                (rules['chats'] as Map).remove(args['id']);
              } else {
                (rules['chats'] as Map)[args['id']] = args['preset'];
              }
              return null;
            case 'saveDefaultPreset':
              pulseStyle = (call.arguments as Map)['preset'] as String;
              return null;
            case 'setPause':
              final minutes = (call.arguments as Map)['minutes'] as int;
              rules['pauseUntil'] = minutes == -1
                  ? -1
                  : minutes == 0
                  ? 0
                  : DateTime.now().millisecondsSinceEpoch + minutes * 60000;
              rules['silenceReason'] = minutes == 0 ? null : 'paused';
              return null;
            case 'saveQuietHours':
              final args = call.arguments as Map;
              rules.addAll({
                'quietEnabled': args['enabled'],
                'startMinute': args['startMinute'],
                'endMinute': args['endMinute'],
              });
              return null;
            case 'previewPreset':
              return null;
            case 'setPulseStyle':
              pulseStyle = (call.arguments as Map)['style'] as String;
              return null;
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
          if (call.method == 'tap') {
            lastTapArguments = call.arguments;
            return {'intensity': 3, 'verified': true};
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
    if (key == 'nav-lab') {
      await tester.tap(find.byKey(const ValueKey('nav-device')));
      await tester.pumpAndSettle();
    }
    if (key == 'app-picker' ||
        key == 'conversation-picker' ||
        (key == 'capture-conversations' &&
            find.text('Who can reach your wrist?').evaluate().isEmpty)) {
      await tester.tap(find.byKey(const ValueKey('nav-rules')));
      await tester.pumpAndSettle();
      if (key == 'app-picker') return;
      if (key == 'capture-conversations') {
        await tester.tap(find.byKey(const ValueKey('conversation-picker')));
        await tester.pumpAndSettle();
      }
    }
    final target = find.byKey(ValueKey(key));
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(BottomSheet).evaluate().isNotEmpty
            ? find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first
            : find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('app header fits narrow screens with large system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester);
    expect(
      find.byKey(const ValueKey('about-air-relay')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tap(tester, 'about-air-relay');
    expect(
      find.textContaining('independent notification companion'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('requires notification access and keeps setup actionable', (
    tester,
  ) async {
    await mount(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('relay-toggle')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('relay-toggle')))
          .onPressed,
      isNull,
    );
    await tap(tester, 'notification-access-settings');
    await tester.pumpAndSettle();
    expect(calls, contains('settings'));
    expect(calls, isNot(contains('start')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('default preset can change while relay is running', (
    tester,
  ) async {
    access = true;
    running = true;
    await mount(tester);
    await tap(tester, 'nav-rules');
    await tap(tester, 'default-vibration');
    await tap(tester, 'preset-double');
    await tap(tester, 'save-rule');
    expect(controller.settings.defaultPreset, VibrationPreset.doublePulse);
    expect(running, isTrue);
    expect(calls, isNot(contains('stop')));
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
    await tester.scrollUntilVisible(
      find.text('Notification access: not enabled'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('app-search')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('app-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('app-search')), 'whats');
    await tester.pumpAndSettle();
    expect(controller.filteredApps.single['packageName'], 'com.whatsapp');
    await tap(tester, 'app-enabled-com.whatsapp');
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
      expect(calls, contains('previewPreset'));
      expect(calls, isNot(contains('vibrate')));
      expect(running, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('test vibration follows the selected style when relay is off', (
    tester,
  ) async {
    access = true;
    await mount(tester);
    await tap(tester, 'test-vibration');
    expect(calls, contains('tap'));
    expect(calls, isNot(contains('vibrate')));
    expect(find.text('Sent'), findsOneWidget);
    expect(find.byKey(const ValueKey('operation-owner')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Try it'), findsOneWidget);
    await controller.setPulseStyle('double');
    await tester.pumpAndSettle();
    calls.clear();
    await tap(tester, 'test-vibration');
    expect(calls, contains('vibrate'));
    expect(calls, isNot(contains('tap')));
    await tester.pumpWidget(const SizedBox());
  });

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
  testWidgets(
    'capture and select chats locally without leaking report identities',
    (tester) async {
      access = true;
      await mount(tester);
      await tap(tester, 'conversation-picker');
      await tester.tap(find.text('Selected'));
      await tester.pumpAndSettle();
      expect(controller.restrictedConversations, isTrue);
      await tap(tester, 'capture-conversations');
      expect(controller.captureRemainingMillis, 60000);
      await tester.enterText(
        find.byKey(const ValueKey('chat-search')),
        'Nobody',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No matching people found. Try another name.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-search')),
        'alice',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'conversation-abcdef012345');
      expect(controller.allowedConversations.single['label'], 'Private Alice');
      expect(controller.exportJson(), isNot(contains('Private Alice')));
      expect(controller.exportJson(), isNot(contains('abcdef012345')));
      expect(
        controller.report()['relay'],
        containsPair('allowedConversationCount', 1),
      );
      await tap(tester, 'done-adding-people');
      expect(controller.captureRemainingMillis, 0);
      expect(
        find.byKey(const ValueKey('chat-rule-abcdef012345')),
        findsOneWidget,
      );
      expect(controller.restrictedConversations, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('editing people asks before stopping an active relay', (
    tester,
  ) async {
    access = true;
    running = true;
    await mount(tester);
    await tap(tester, 'conversation-picker');
    await tap(tester, 'capture-conversations');
    expect(find.text('Stop relay to edit people?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(running, isTrue);
    expect(calls, isNot(contains('stop')));
    expect(
      () => controller.configureConversations('clearConversations'),
      throwsStateError,
    );
    expect(calls, isNot(contains('clearConversations')));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'name-only chat requires confirmation and stays selectable after listening stops',
    (tester) async {
      access = true;
      nameCandidate = true;
      await mount(tester);
      await tap(tester, 'capture-conversations');
      conversations['captureRemainingMillis'] = 0;
      await controller.refresh();
      await tester.pumpAndSettle();
      await tap(tester, 'conversation-abcdef012345');
      expect(find.text('Match this chat by name?'), findsOneWidget);
      await tap(tester, 'cancel-name-match');
      expect(lastSelection, isNull);
      await tap(tester, 'conversation-abcdef012345');
      await tap(tester, 'confirm-name-match');
      expect(lastSelection?['allowNameMatch'], isTrue);
      expect(controller.allowedConversations, hasLength(1));
      expect(controller.exportJson(), isNot(contains('Private Alice')));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Home pause and resume preserve the running relay', (
    tester,
  ) async {
    access = true;
    running = true;
    await mount(tester);
    await tap(tester, 'pause-relay');
    await tester.tap(find.text('Pause for 15 minutes'));
    await tester.pumpAndSettle();
    expect(controller.settings.silenceReason, 'paused');
    expect(running, isTrue);
    await tap(tester, 'resume-relay');
    expect(controller.settings.silenceReason, isNull);
    expect(calls, isNot(contains('stop')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'preset preview does not save and explicit strength is disclosed',
    (tester) async {
      access = true;
      running = true;
      await mount(tester);
      await tap(tester, 'nav-rules');
      await tap(tester, 'default-vibration');
      await tap(tester, 'preset-low');
      expect(
        find.textContaining('It keeps that strength afterward'),
        findsOneWidget,
      );
      await tap(tester, 'preview-rule');
      expect(calls, contains('previewPreset'));
      expect(calls, isNot(contains('saveDefaultPreset')));
      expect(controller.settings.defaultPreset, VibrationPreset.single);
      expect(find.text('Command verified. Did you feel it?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a chat inherits its app preset when previewed without saving', (
    tester,
  ) async {
    access = true;
    selected.add('com.whatsapp');
    (rules['apps'] as Map)['com.whatsapp'] = {'enabled': true, 'preset': 'low'};
    conversations['allowed'] = [
      {'id': 'private-chat', 'label': 'Alice', 'packageName': 'com.whatsapp'},
    ];
    await mount(tester);
    await tap(tester, 'nav-rules');
    await tap(tester, 'conversation-picker');
    await tap(tester, 'chat-rule-private-chat');
    expect(find.text('Use app vibration'), findsOneWidget);
    await tap(tester, 'preview-rule');
    expect(lastTapArguments, {'intensity': 2});
    expect(calls, isNot(contains('saveChatRule')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quiet hours save without stopping the relay', (tester) async {
    access = true;
    running = true;
    await mount(tester);
    await tap(tester, 'nav-rules');
    await tap(tester, 'quiet-hours');
    await tap(tester, 'quiet-enabled');
    await tap(tester, 'save-quiet-hours');
    expect(controller.settings.quietEnabled, isTrue);
    expect(running, isTrue);
    expect(calls, isNot(contains('stop')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zero-event diagnostics remain visible after capture ends', (
    tester,
  ) async {
    access = true;
    conversations['diagnostics'] = {'seen': 0, 'privateLabel': 'SECRET'};
    await mount(tester);
    await tap(tester, 'nav-rules');
    await tap(tester, 'capture-conversations');
    conversations['candidates'] = <Map<String, Object?>>[];
    await controller.refresh();
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('capture-diagnostics'));
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No WhatsApp notifications found'),
      findsOneWidget,
    );
    expect(controller.captureDiagnostics, {'seen': 0});
    expect(controller.exportJson(), isNot(contains('SECRET')));
    await tester.pumpWidget(const SizedBox());
  });
}
