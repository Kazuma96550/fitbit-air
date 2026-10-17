import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fitbit_air/fitbit_air.dart';

import 'app_icon.dart';
import 'app_theme.dart';
import 'demo_controller.dart';

Future<void> showRelaySetup(
  BuildContext context,
  DemoController controller, {
  int initialStep = 0,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        RelaySetupPage(controller: controller, initialStep: initialStep),
  ),
);

class RelaySetupPage extends StatefulWidget {
  const RelaySetupPage({
    super.key,
    required this.controller,
    this.initialStep = 0,
  });
  final DemoController controller;
  final int initialStep;
  @override
  State<RelaySetupPage> createState() => _RelaySetupPageState();
}

class _RelaySetupPageState extends State<RelaySetupPage> {
  late int step = widget.initialStep;
  bool working = false;
  bool sent = false;
  bool felt = false;
  String query = '';
  String? error;
  DemoController get state => widget.controller;
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void go(int value) {
    setState(() {
      step = value;
      error = null;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = switch (failure) {
            PlatformException error => DemoController.recoveryHint(error.code),
            FitbitAirException error => DemoController.recoveryHint(error.code),
            _ =>
              'That did not finish. Check the Air and your permissions, then try again.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> finish({required bool feltVibration}) async {
    if (!state.setupRequirementsMet) {
      go(
        !state.bluetoothPermission ||
                state.bluetoothEnabled != true ||
                state.paired != true
            ? 0
            : !state.access || !state.listenerConnected
            ? 1
            : 2,
      );
      return;
    }
    await state.completeSetup();
    if (!mounted) return;
    felt = feltVibration;
    go(4);
  }

  Widget note(IconData icon, String title, String text, {bool done = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              done ? Icons.check_circle_outline : icon,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final connected =
          state.bluetoothPermission &&
          state.bluetoothEnabled == true &&
          state.paired == true;
      final notifications = state.access && state.listenerConnected;
      final blocked =
          working ||
          state.busy ||
          state.previewing ||
          state.changingRelay ||
          state.relayStopping;
      final titles = [
        'Meet your Air.',
        'Only the alerts you want.',
        'Make room for what matters.',
        'Feel your first nudge.',
        'You’re ready.',
      ];
      final descriptions = [
        'Keep your band nearby. We’ll use the Air you already paired in Google Health.',
        'Give Air Relay permission to turn selected notifications into a vibration.',
        'Pick the apps that can reach your wrist. You can change these anytime in Rules.',
        state.relayRunning
            ? 'Send one test vibration, then tell us if you felt it. Your existing relay keeps running.'
            : 'Send one test vibration, then tell us if you felt it. Notifications stay off until you start them.',
        felt
            ? 'Your Air is paired, permissions are ready, and you felt the test vibration.'
            : 'Your settings are ready. You can try a vibration from Home whenever you like.',
      ];
      final apps =
          state.apps
              .where(
                (app) => '${app['label']} ${app['packageName']}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
              )
              .toList()
            ..sort(
              (a, b) => (a['label'] as String).toLowerCase().compareTo(
                (b['label'] as String).toLowerCase(),
              ),
            );
      return PopScope(
        canPop: !working,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Set up Air Relay'),
            actions: [
              IconButton(
                key: const ValueKey('close-setup'),
                tooltip: 'Close setup',
                onPressed: working ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step == 4
                            ? 'READY TO GO'
                            : 'STEP ${step + 1} OF 4 · ${['Connect', 'Permissions', 'Apps', 'Try it'][step]}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          letterSpacing: .7,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(
                          4,
                          (index) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: index == 3 ? 0 : 6,
                              ),
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: index <= step
                                      ? colors.primary
                                      : colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: step == 4
                            ? Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: colors.primary,
                              )
                            : const AirRelayMark(size: 64),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        titles[step],
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.6,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        descriptions[step],
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (step == 0) ...[
                        note(
                          Icons.bluetooth,
                          'Nearby devices',
                          state.bluetoothPermission
                              ? 'Bluetooth permission is allowed.'
                              : 'Android will ask to let Air Relay find and connect to nearby devices.',
                          done: state.bluetoothPermission,
                        ),
                        note(
                          Icons.watch_outlined,
                          'Paired in Google Health',
                          state.paired == true
                              ? 'Your paired Air was found. This does not mean it is currently connected.'
                              : 'Pair your Air in Google Health first, then check it here.',
                          done: state.paired == true,
                        ),
                        if (connected)
                          TextButton(
                            onPressed: blocked
                                ? null
                                : () => run(state.checkPaired),
                            child: const Text('Check again'),
                          ),
                        if (!state.bluetoothPermission)
                          TextButton(
                            onPressed: blocked
                                ? null
                                : () => run(state.openAppSettings),
                            child: const Text(
                              'Permission blocked? Open app settings',
                            ),
                          ),
                        if (state.paired == false)
                          const Text(
                            'No paired Air found. Open Google Health, finish pairing, then return and check again.',
                          ),
                      ],
                      if (step == 1) ...[
                        Card(
                          color: colors.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  color: colors.onPrimaryContainer,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Your notifications stay yours.',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: colors.onPrimaryContainer,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Air Relay reads notifications on this phone, even in the background, to match your chosen apps and WhatsApp people. Android grants access to all notifications. We don’t upload them. Saved chat names stay on this phone.',
                                  style: TextStyle(
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        note(
                          Icons.notifications_outlined,
                          notifications
                              ? 'Notification access is ready'
                              : state.access
                              ? 'Waiting for Android'
                              : 'Allow access in Android',
                          notifications
                              ? 'You’re in control of which apps can vibrate.'
                              : state.access
                              ? 'Access is enabled but the listener is not connected yet. Check access if this continues.'
                              : 'On the next screen, choose Air Relay and allow notification access.',
                          done: notifications,
                        ),
                        if (notifications)
                          TextButton(
                            key: const ValueKey('notification-access-settings'),
                            onPressed: blocked
                                ? null
                                : () => run(state.openAccessSettings),
                            child: const Text('Review notification access'),
                          ),
                        if (state.notificationControlsAllowed == false) ...[
                          const SizedBox(height: 16),
                          note(
                            Icons.tune,
                            'Keep pause and stop close by',
                            'Allow Air Relay to show its ongoing notification so you can control it without opening the app. This is recommended, not required.',
                          ),
                          OutlinedButton(
                            key: const ValueKey('setup-notification-controls'),
                            onPressed: blocked
                                ? null
                                : () => run(state.allowNotificationControls),
                            child: const Text('Allow relay controls'),
                          ),
                          TextButton(
                            onPressed: blocked
                                ? null
                                : () => run(
                                    state.openNotificationControlsSettings,
                                  ),
                            child: const Text('Review in Android settings'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'You can revoke this access in Android settings at any time. No account or cloud relay is needed.',
                        ),
                      ],
                      if (step == 2) ...[
                        Text(
                          state.selectedAppsSummary,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('setup-app-search'),
                          decoration: const InputDecoration(
                            labelText: 'Find an app',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) => setState(() => query = value),
                        ),
                        const SizedBox(height: 12),
                        if (apps.isEmpty)
                          const Text(
                            'No matching apps. Try another search or refresh the list.',
                          ),
                        for (final app in apps)
                          SwitchListTile(
                            key: ValueKey('setup-app-${app['packageName']}'),
                            contentPadding: EdgeInsets.zero,
                            secondary: AppIcon(encoded: app['icon'] as String?),
                            title: Text(app['label']! as String),
                            value: state.selectedApps.contains(
                              app['packageName'],
                            ),
                            onChanged: blocked
                                ? null
                                : (value) => run(
                                    () => state.saveAppRule(
                                      app['packageName']! as String,
                                      value,
                                      state
                                          .settings
                                          .apps[app['packageName']]
                                          ?.preset,
                                    ),
                                  ),
                          ),
                        TextButton(
                          onPressed: blocked ? null : () => run(state.loadApps),
                          child: const Text('Refresh apps'),
                        ),
                        if (state.relayRunning)
                          const Text(
                            'Your relay is on. App changes apply to new notifications.',
                          ),
                        const Text(
                          'Choose specific WhatsApp people and custom vibrations later in Rules.',
                        ),
                      ],
                      if (step == 3) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Icon(
                                  sent
                                      ? Icons.vibration
                                      : Icons.waving_hand_outlined,
                                  size: 48,
                                  color: colors.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  sent
                                      ? 'Did you feel it?'
                                      : 'Put your Air on your wrist.',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  sent
                                      ? 'The command was verified. Only you can confirm the vibration.'
                                      : 'We’ll send your default vibration once. This can take a few seconds.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (sent)
                          TextButton(
                            key: const ValueKey('setup-did-not-feel'),
                            onPressed: blocked
                                ? null
                                : () => setState(() {
                                    sent = false;
                                    error =
                                        'Keep your Air nearby and check that vibration is enabled in Google Health. Try once more when ready.';
                                  }),
                            child: const Text('I didn’t feel it'),
                          ),
                        if (state.relayRunning &&
                            state.settings.silenceReason != null)
                          const Text(
                            'Notifications are paused or in quiet hours. Resume on Home before sending a test, or finish without testing.',
                          ),
                      ],
                      if (step == 4) ...[
                        note(
                          Icons.notifications_active_outlined,
                          state.selectedAppsSummary,
                          state.relayRunning
                              ? 'Notifications are already on. Pause anytime from Home.'
                              : 'Start notifications when you’re ready. Pause anytime from Home.',
                        ),
                        note(
                          Icons.tune,
                          'Make it yours',
                          'In Rules, choose people, vibrations and quiet hours.',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Early access: Google Health sync is still being tested. If sync stalls, stop the relay and check Google Health.',
                        ),
                      ],
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: ValueKey(
                          step == 0 && !connected
                              ? 'setup-check-air'
                              : step == 1 && !notifications
                              ? 'notification-access-settings'
                              : 'setup-next',
                        ),
                        onPressed:
                            blocked ||
                                (step == 2 && state.selectedApps.isEmpty) ||
                                (step == 3 &&
                                    !sent &&
                                    state.relayRunning &&
                                    state.settings.silenceReason != null)
                            ? null
                            : () {
                                if (step == 0 && !connected) {
                                  run(
                                    state.bluetoothPermission &&
                                            state.bluetoothEnabled == false
                                        ? state.openBluetoothSettings
                                        : state.checkPaired,
                                  );
                                } else if (step == 1 && !notifications) {
                                  run(state.openAccessSettings);
                                } else if (step < 3) {
                                  go(step + 1);
                                } else if (step == 3 && !sent) {
                                  run(() async {
                                    await state.previewPreset(
                                      state.settings.defaultPreset,
                                    );
                                    if (mounted) setState(() => sent = true);
                                  });
                                } else if (step == 3) {
                                  run(() => finish(feltVibration: true));
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                        child: working
                            ? Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  Text(
                                    step == 3 && !sent
                                        ? 'Sending…'
                                        : 'Please wait…',
                                  ),
                                ],
                              )
                            : Text(
                                step == 0 && !connected
                                    ? !state.bluetoothPermission
                                          ? 'Allow nearby devices'
                                          : state.bluetoothEnabled == false
                                          ? 'Turn on Bluetooth'
                                          : 'Check my Air'
                                    : step == 1 && !notifications
                                    ? state.access
                                          ? 'Check notification access'
                                          : 'Allow notification access'
                                    : step < 3
                                    ? 'Continue'
                                    : step == 3
                                    ? sent
                                          ? 'Yes, I felt it'
                                          : 'Send test vibration'
                                    : 'Go to Home',
                              ),
                      ),
                      if (step == 3)
                        TextButton(
                          key: const ValueKey('setup-skip-test'),
                          onPressed: blocked
                              ? null
                              : () => run(() => finish(feltVibration: false)),
                          child: const Text('Finish without testing'),
                        ),
                      if (step > 0 && step < 4)
                        TextButton(
                          onPressed: blocked ? null : () => go(step - 1),
                          child: const Text('Back'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
