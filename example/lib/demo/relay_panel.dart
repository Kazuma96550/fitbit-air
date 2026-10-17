import 'dart:convert';

import 'package:flutter/material.dart';

import 'demo_controller.dart';
import 'conversation_picker.dart';

class RelayPanel extends StatelessWidget {
  const RelayPanel({
    super.key,
    required this.controller,
    required this.perform,
    required this.testVibration,
    required this.exportReport,
  });
  final DemoController controller;
  final void Function(Future<void> Function()) perform;
  final VoidCallback testVibration;
  final VoidCallback exportReport;

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

  @override
  Widget build(BuildContext context) {
    final state = controller;
    final apps = state.filteredApps;
    return ListView(
      key: const ValueKey('relay-scroll'),
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
                            : state.relayRunning
                            ? 'Your relay is on'
                            : 'Your relay is paused',
                        key: const ValueKey('relay-status'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.relayOutcome,
                    key: const ValueKey('relay-outcome'),
                  ),
                ),
                if (state.setupError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      state.setupError!,
                      key: const ValueKey('relay-error'),
                    ),
                  ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('test-vibration'),
                  onPressed:
                      state.busy ||
                          state.changingRelay ||
                          state.relayStopping ||
                          (state.relayRunning && !state.relayReady)
                      ? null
                      : testVibration,
                  icon: const Icon(Icons.vibration),
                  label: const Text('Test vibration'),
                ),
                if (state.trials.isNotEmpty &&
                    state.trials.first['operation'] == 'preview')
                  Text(
                    'Test vibration: ${state.trials.first['outcome'] == 'completed'
                        ? 'command verified; mark below if you felt it'
                        : state.trials.first['errorCode'] == null
                        ? state.trials.first['outcome']
                        : DemoController.recoveryHint(state.trials.first['errorCode']! as String)}',
                    key: const ValueKey('test-vibration-result'),
                  ),
                if (state.trials.isNotEmpty || state.history.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('marker-felt-vibration'),
                    onPressed: () => state.mark('felt_vibration'),
                    icon: const Icon(Icons.touch_app),
                    label: const Text('Mark: I felt vibration'),
                  ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  key: const ValueKey('pulse-style'),
                  segments: const [
                    ButtonSegment(
                      value: 'double',
                      label: Text('Two pulses'),
                      icon: Icon(Icons.restore),
                    ),
                    ButtonSegment(
                      value: 'single',
                      label: Text('One pulse'),
                      icon: Icon(Icons.swap_vert),
                    ),
                  ],
                  selected: {state.pulseStyle},
                  onSelectionChanged:
                      state.relayRunning || state.changingRelay || state.busy
                      ? null
                      : (value) =>
                            perform(() => state.setPulseStyle(value.single)),
                ),
                const SizedBox(height: 8),
                Text(
                  state.pulseStyle == 'single'
                      ? 'One pulse per alert. The Air only buzzes when its strength changes, so each alert switches between low and high.'
                      : 'Two pulses per alert. Your original vibration strength is restored afterward.',
                  key: const ValueKey('pulse-style-hint'),
                ),
                if (state.relayRunning)
                  const Text('Stop the relay to change the pulse style.'),
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
          child: ExpansionTile(
            key: const ValueKey('app-picker'),
            leading: const Icon(Icons.apps_rounded),
            title: const Text('Choose notification apps'),
            subtitle: Text(
              state.selectedApps.isEmpty
                  ? 'Choose at least one app'
                  : '${state.selectedApps.length} selected · ${state.selectedApps.map((package) => state.apps.where((app) => app['packageName'] == package).map((app) => app['label'] as String).firstOrNull ?? package.split('.').last).join(', ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            childrenPadding: const EdgeInsets.all(12),
            children: [
              TextFormField(
                key: const ValueKey('app-search'),
                initialValue: state.appSearch,
                decoration: const InputDecoration(
                  labelText: 'Search apps',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: state.searchApps,
              ),
              const SizedBox(height: 8),
              if (state.selectedApps.isEmpty)
                const Text('Select at least one app before starting.'),
              if (state.relayRunning)
                const Text('Stop the relay to change selected apps.'),
              if (apps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No matching apps. Try another search or refresh the list.',
                  ),
                )
              else
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    key: const ValueKey('app-list'),
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      final packageName = app['packageName']! as String;
                      final icon = app['icon'] as String?;
                      return CheckboxListTile(
                        key: ValueKey('app-$packageName'),
                        secondary: icon == null
                            ? const Icon(Icons.apps)
                            : Image.memory(
                                base64Decode(icon),
                                width: 32,
                                height: 32,
                                gaplessPlayback: true,
                              ),
                        title: Text(app['label']! as String),
                        value: state.selectedApps.contains(packageName),
                        onChanged: state.relayRunning || state.changingRelay
                            ? null
                            : (value) => perform(
                                () => state.selectApp(packageName, value!),
                              ),
                      );
                    },
                  ),
                ),
              TextButton(
                key: const ValueKey('refresh-apps'),
                onPressed: () => perform(state.loadApps),
                child: const Text('Refresh app list'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConversationPicker(controller: state, perform: perform),
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
                      entry['stage'] != 'queued',
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
