import 'dart:convert';

import 'package:flutter/material.dart';

import 'demo_controller.dart';

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
        : TextButton(onPressed: action, child: Text(actionLabel ?? 'Set up')),
  );

  @override
  Widget build(BuildContext context) {
    final state = controller;
    final apps = state.filteredApps;
    return ListView(
      key: const ValueKey('relay-scroll'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Notifications → Air',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Relay selected app notifications as two pulses, with the original strength restored.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Setup', style: Theme.of(context).textTheme.titleMedium),
                _check(
                  'Notification access: ${state.access ? (state.listenerConnected ? "connected" : "connecting") : "not enabled"}',
                  state.access && state.listenerConnected,
                  action: () => perform(state.openAccessSettings),
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
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Relay: ${state.relayRunning ? (state.relayStopping ? "stopping" : "on") : "off"}',
                    key: const ValueKey('relay-status'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(state.relayOutcome, key: const ValueKey('relay-outcome')),
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
                TextButton.icon(
                  key: const ValueKey('marker-felt-vibration'),
                  onPressed: () => state.mark('felt_vibration'),
                  icon: const Icon(Icons.touch_app),
                  label: const Text('Mark: I felt vibration'),
                ),
                const Text(
                  'A verified command is not physical-delivery confirmation. Start the relay again after a restart.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            key: const ValueKey('app-picker'),
            title: const Text('Choose notification apps'),
            subtitle: Text('${state.selectedApps.length} selected'),
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
        _conversations(context),
        const SizedBox(height: 16),
        Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Times below are phone receipt times. Queue time and Bluetooth setup are included in total latency.',
        ),
        if (state.history.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No relay activity yet. Start the relay and send a notification, or use Test vibration.',
            ),
          ),
        for (final entry in state.history.take(100)) _activity(context, entry),
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

  Widget _conversations(BuildContext context) {
    final state = controller;
    final blocked = state.relayRunning || state.changingRelay;
    final allowedIds = state.allowedConversations
        .map((item) => item['id'])
        .toSet();
    final chats = [
      ...state.allowedConversations,
      ...state.conversationCandidates.where(
        (item) => !allowedIds.contains(item['id']),
      ),
    ];
    void configure(String method, [Object? arguments]) =>
        perform(() => state.configureConversations(method, arguments));
    return Card(
      child: ExpansionTile(
        key: const ValueKey('conversation-picker'),
        title: const Text('WhatsApp conversations'),
        subtitle: Text(
          state.restrictedConversations
              ? 'Only selected chats · ${allowedIds.length} selected'
              : 'All chats in selected WhatsApp apps',
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          const Text(
            'For one person, select their direct chat. Selecting a group allows everyone in that group. Applies to WhatsApp and WhatsApp Business; other selected apps stay unchanged.',
          ),
          SwitchListTile(
            key: const ValueKey('restrict-conversations'),
            title: const Text('Only selected WhatsApp chats'),
            value: state.restrictedConversations,
            onChanged: blocked
                ? null
                : (value) =>
                      configure('restrictConversations', {'enabled': value}),
          ),
          if (state.restrictedConversations && allowedIds.isEmpty)
            const Text(
              'No WhatsApp chats allowed. Capture a notification and select a chat below.',
            ),
          if (blocked)
            const Text('Stop the relay to capture or change conversations.'),
          const Text(
            'Capture reads conversation names and IDs locally for 60 seconds, without vibrating. Have someone send a fresh notification while their chat is closed. Message text is never read. Names and IDs are excluded from reports.',
          ),
          OutlinedButton(
            key: const ValueKey('capture-conversations'),
            onPressed: blocked || (!state.access || !state.listenerConnected)
                ? null
                : () => configure('captureConversations', {
                    'enabled': state.captureRemainingMillis == 0,
                  }),
            child: Text(
              state.captureRemainingMillis > 0
                  ? 'Stop capture (${(state.captureRemainingMillis / 1000).ceil()} s)'
                  : 'Capture chats for 60 seconds',
            ),
          ),
          if (state.unsupportedConversations > 0)
            const Text(
              'A WhatsApp notification had no conversation ID. It cannot be selected or allowed in restricted mode.',
            ),
          const Text(
            'Names are labels only; matching requires Android’s conversation ID. If WhatsApp omits or changes that ID, capture again. Restricted mode skips unidentified chats. Saved selections stay on this device until removed or app data is cleared.',
          ),
          if (chats.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView.builder(
                key: const ValueKey('conversation-list'),
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  final id = chat['id']! as String;
                  final selected = allowedIds.contains(id);
                  return CheckboxListTile(
                    key: ValueKey('conversation-$id'),
                    title: Text(chat['label']! as String),
                    subtitle: Text(
                      '${chat['packageName'] == 'com.whatsapp.w4b' ? 'WhatsApp Business' : 'WhatsApp'} · ID …${id.substring(id.length - 6)}',
                    ),
                    value: selected,
                    onChanged: blocked
                        ? null
                        : (value) => configure('selectConversation', {
                            'id': id,
                            'enabled': value,
                          }),
                  );
                },
              ),
            ),
          TextButton(
            key: const ValueKey('clear-conversations'),
            onPressed: blocked ? null : () => configure('clearConversations'),
            child: const Text('Forget all selected and captured chats'),
          ),
        ],
      ),
    );
  }

  Widget _activity(BuildContext context, Map<String, Object?> entry) {
    final stage = entry['stage'] as String? ?? 'unknown';
    final title = switch (stage) {
      'detected' => 'Notification detected',
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
      key: ValueKey('activity-${entry['commandId']}-$stage'),
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
