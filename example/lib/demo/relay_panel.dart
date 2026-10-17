import 'package:flutter/material.dart';

import 'demo_controller.dart';
import 'rules_panel.dart';

class RelayPanel extends StatelessWidget {
  const RelayPanel({
    super.key,
    required this.controller,
    required this.perform,
    required this.testVibration,
    required this.exportReport,
    this.testFeedback,
    this.openRules,
    this.scrollController,
  });
  final DemoController controller;
  final void Function(Future<void> Function()) perform;
  final VoidCallback testVibration;
  final VoidCallback exportReport;
  final VoidCallback? openRules;
  final ScrollController? scrollController;

  /// Inline Test state: null (idle), 'sending' or 'sent'.
  final String? testFeedback;

  /// Routine outcomes the title already conveys; errors still show.
  static bool _routine(String outcome) =>
      outcome == 'Relay stopped.' ||
      outcome == 'Relay is off.' ||
      outcome.startsWith('Haptic ');

  Widget _check(
    String label,
    bool? complete, {
    VoidCallback? action,
    String? actionLabel,
    String? actionKey,
  }) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      complete == true
          ? Icons.check_circle
          : complete == false
          ? Icons.error_outline
          : Icons.help_outline,
      color: complete == true ? Colors.green : null,
    ),
    title: Text(label),
    trailing: action == null
        ? null
        : TextButton(
            key: actionKey == null ? null : ValueKey(actionKey),
            onPressed: action,
            child: Text(actionLabel ?? 'Set up'),
          ),
  );

  /// Fixed-size so progress and confirmation never move the layout.
  Widget _testButton(BuildContext context, DemoController state) {
    final sending = testFeedback == 'sending';
    final sent = testFeedback == 'sent';
    final enabled =
        testFeedback == null &&
        !state.busy &&
        !state.previewing &&
        !state.changingRelay &&
        !state.relayStopping &&
        (!state.relayRunning || state.settings.silenceReason == null) &&
        (!state.relayRunning || state.relayReady);
    return Semantics(
      label: 'Test vibration',
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 112),
        child: TextButton.icon(
          key: const ValueKey('test-vibration'),
          onPressed: enabled ? testVibration : null,
          // Keep progress and confirmation in the accent colour, not greyed.
          style: sending || sent
              ? TextButton.styleFrom(
                  disabledForegroundColor: Theme.of(
                    context,
                  ).colorScheme.primary,
                )
              : null,
          icon: sending
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : Icon(sent ? Icons.check : Icons.vibration, size: 18),
          label: Text(
            sending
                ? 'Sending…'
                : sent
                ? 'Sent'
                : 'Try it',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = controller;

    return ListView(
      key: const ValueKey('relay-scroll'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'A little nudge.\nRight on your wrist.',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the notifications that reach your Fitbit Air.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        state.relayRunning
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_paused_outlined,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.relayStopping
                            ? 'Finishing up'
                            : !state.relayRunning
                            ? 'Relay is off'
                            : state.settings.silenceReason == 'paused'
                            ? 'Taking a break'
                            : state.settings.silenceReason == 'quiet_hours'
                            ? 'Quiet hours'
                            : 'Listening for your notifications',
                        key: const ValueKey('relay-status'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (state.relayRunning || !_routine(state.relayOutcome))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        state.relayOutcome,
                        key: const ValueKey('relay-outcome'),
                      ),
                    ),
                  ),
                if (state.setupError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      state.setupError!,
                      key: const ValueKey('relay-error'),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('relay-toggle'),
                  onPressed:
                      state.changingRelay ||
                          state.relayStopping ||
                          (!state.relayRunning &&
                              (state.busy ||
                                  state.selectedApps.isEmpty ||
                                  !state.access ||
                                  !state.listenerConnected ||
                                  state.bluetoothEnabled == false))
                      ? null
                      : () => perform(
                          state.relayRunning
                              ? state.stopRelay
                              : state.startRelay,
                        ),
                  icon: Icon(
                    state.relayRunning ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(
                    state.relayRunning
                        ? 'Stop notification relay'
                        : 'Start notification relay',
                  ),
                ),
                if (state.relayRunning) ...[
                  const SizedBox(height: 12),
                  if (state.settings.silenceReason == 'paused')
                    Text(
                      state.settings.pauseUntil == -1
                          ? 'Paused until you resume.'
                          : 'Paused until ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(state.settings.pauseUntil)).format(context)}.',
                    ),
                  if (state.settings.silenceReason == 'quiet_hours')
                    Text(
                      'Quiet until ${formatMinute(context, state.settings.endMinute)}. No missed alerts will be replayed.',
                    ),
                  if (state.settings.silenceReason == 'paused')
                    OutlinedButton.icon(
                      key: const ValueKey('resume-relay'),
                      onPressed: state.changingRelay
                          ? null
                          : () => perform(() => state.setPause(0)),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume notifications'),
                    )
                  else
                    PopupMenuButton<int>(
                      key: const ValueKey('pause-relay'),
                      tooltip: 'Pause notifications',
                      enabled: !state.changingRelay,
                      onSelected: (minutes) =>
                          perform(() => state.setPause(minutes)),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 15,
                          child: Text('Pause for 15 minutes'),
                        ),
                        PopupMenuItem(
                          value: 60,
                          child: Text('Pause for 1 hour'),
                        ),
                        PopupMenuItem(
                          value: -1,
                          child: Text('Pause until I resume'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.pause),
                            SizedBox(width: 8),
                            Text('Take a break'),
                          ],
                        ),
                      ),
                    ),
                ],
                const Divider(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Default · ${state.settings.defaultPreset.label}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    _testButton(context, state),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            key: ValueKey(
              'relay-setup-${!state.access || !state.listenerConnected || state.bluetoothEnabled == false}',
            ),
            initiallyExpanded:
                !state.access ||
                !state.listenerConnected ||
                state.bluetoothEnabled == false,
            leading: Icon(
              state.access &&
                      state.listenerConnected &&
                      state.bluetoothEnabled == true
                  ? Icons.check_circle_outline
                  : Icons.settings_outlined,
            ),
            title: const Text('Device & permissions'),
            subtitle: Text(
              state.access &&
                      state.listenerConnected &&
                      state.bluetoothEnabled == true
                  ? 'Notification access connected · Bluetooth on'
                  : 'Complete setup to relay notifications',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _check(
                      'Notification access: ${state.access ? (state.listenerConnected ? "connected" : "connecting") : "not enabled"}',
                      state.access && state.listenerConnected,
                      action: () => perform(state.openAccessSettings),
                      actionKey: 'notification-access-settings',
                      actionLabel: 'Settings',
                    ),
                    _check(
                      'Nearby devices permission',
                      state.bluetoothPermission,
                      action: state.controlsBlocked
                          ? null
                          : () => perform(state.checkPaired),
                      actionLabel: 'Check',
                    ),
                    _check(
                      'Bluetooth ${state.bluetoothEnabled == true
                          ? "on"
                          : state.bluetoothEnabled == false
                          ? "off"
                          : "not checked"}',
                      state.bluetoothEnabled,
                      action: () => perform(state.openBluetoothSettings),
                      actionLabel: 'Settings',
                    ),
                    _check(
                      state.paired == true
                          ? 'Air paired in Google Health'
                          : 'Air pairing ${state.paired == false ? "not found" : "not checked"}',
                      state.paired,
                      action: state.controlsBlocked
                          ? null
                          : () => perform(state.checkPaired),
                      actionLabel: 'Check',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            key: const ValueKey('home-rules'),
            leading: const Icon(Icons.tune),
            title: const Text('Your notification rules'),
            subtitle: Text(
              '${state.selectedApps.length} apps selected · Custom vibrations and quiet hours',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: openRules,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Early access · Google Health sync is still being tested. If sync stalls after a vibration, pause the relay.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (state.history.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No relay activity yet. Start the relay and send a notification, or use Test vibration.',
            ),
          ),
        for (final entry
            in state.history
                .where(
                  (entry) =>
                      entry['stage'] != 'detected' &&
                      entry['stage'] != 'queued' &&
                      entry['stage'] != 'merged',
                )
                .take(5))
          _activity(context, entry),
        if (state.history.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('activity-details'),
            title: const Text('Delivery details'),
            subtitle: const Text('Timing, queue events and troubleshooting'),
            children: [
              for (final entry in state.history.take(100))
                _activity(context, entry, detailed: true),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('export-report'),
              onPressed: exportReport,
              icon: const Icon(Icons.copy),
              label: const Text('Copy sanitized report'),
            ),
            TextButton(
              key: const ValueKey('clear-history'),
              onPressed: state.changingRelay
                  ? null
                  : () => perform(state.clearHistory),
              child: const Text('Clear relay history'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activity(
    BuildContext context,
    Map<String, Object?> entry, {
    bool detailed = false,
  }) {
    final stage = entry['stage'] as String? ?? 'unknown';
    final title = switch (stage) {
      'detected' => 'Notification detected',
      'combined' => 'Combined into one vibration',
      'paused' => 'Quiet: notifications paused',
      'quiet_hours' => 'Quiet: scheduled quiet hours',
      'filtered' => 'Skipped by your rules',
      'merged' => 'Merged into next vibration',
      'queued' => 'Queued',
      'verified' => 'Command verified',
      'expired' => 'Expired before execution',
      'queue_full' => 'Dropped: queue full',
      'cancelled' => 'Cancelled before execution',
      'duplicate' => 'Duplicate suppressed',
      'interrupted' => 'Interrupted; delivery uncertain',
      _ => 'Command failed',
    };
    final packageName = entry['sourcePackage'];
    final source = packageName == null
        ? 'Test vibration'
        : controller.apps
                  .where((app) => app['packageName'] == packageName)
                  .map((app) => app['label'] as String)
                  .firstOrNull ??
              'Selected app';
    final millis = entry['atMillis'] as int?;
    final time = millis == null
        ? ''
        : TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(millis),
          ).format(context);
    final code = entry['errorCode'] as String?;
    return ListTile(
      key: ValueKey(
        '${detailed ? "detail" : "activity"}-${entry['commandId']}-$stage',
      ),
      leading: Icon(
        stage == 'verified'
            ? Icons.check_circle_outline
            : stage == 'failed' || stage == 'interrupted'
            ? Icons.error_outline
            : Icons.history,
      ),
      title: Text('$source · $title'),
      subtitle: Text(
        '$time${entry['latencyMillis'] == null ? "" : " · ${entry['latencyMillis']} ms total"}${code == null ? "" : "\n${DemoController.recoveryHint(code)}"}',
      ),
    );
  }
}
