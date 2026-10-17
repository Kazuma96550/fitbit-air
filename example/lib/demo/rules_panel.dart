import 'dart:convert';
import 'package:flutter/material.dart';
import 'demo_controller.dart';
import 'conversation_picker.dart';
import 'vibration_editor.dart';

class RulesPanel extends StatelessWidget {
  const RulesPanel({
    super.key,
    required this.controller,
    required this.perform,
    this.scrollController,
  });
  final DemoController controller;
  final ScrollController? scrollController;
  final void Function(Future<void> Function()) perform;
  @override
  Widget build(BuildContext context) {
    final state = controller;
    return ListView(
      key: const ValueKey('rules-scroll'),
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Make each nudge yours.',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose which apps reach your wrist and how they feel. Changes apply to new notifications.',
        ),
        const SizedBox(height: 20),
        ConversationPicker(controller: state, perform: perform),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            key: const ValueKey('default-vibration'),
            leading: const Icon(Icons.vibration),
            title: const Text('Default vibration'),
            subtitle: Text(state.settings.defaultPreset.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => editVibration(
              context,
              state,
              title: 'Default vibration',
              initial: state.settings.defaultPreset,
              allowDefault: false,
              onSave: (preset) => state.saveDefaultPreset(preset!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            key: const ValueKey('quiet-hours'),
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Quiet hours'),
            subtitle: Text(
              state.settings.quietEnabled
                  ? '${formatMinute(context, state.settings.startMinute)} to ${formatMinute(context, state.settings.endMinute)} · Every day'
                  : 'Off · Set a daily time to stay quiet',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => editQuietHours(context, state),
          ),
        ),
        const SizedBox(height: 24),
        Text('Your apps', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('app-search'),
          initialValue: state.appSearch,
          decoration: const InputDecoration(
            labelText: 'Search apps',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: state.searchApps,
        ),
        const SizedBox(height: 12),
        if (state.filteredApps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No matching apps. Try another search or refresh the list.',
            ),
          ),
        for (final app in state.filteredApps)
          Builder(
            builder: (context) {
              final pkg = app['packageName']! as String;
              final rule = state.settings.apps[pkg];
              final enabled = state.selectedApps.contains(pkg);
              final preset = rule?.preset;
              final icon = app['icon'] as String?;
              return ListTile(
                key: ValueKey('app-$pkg'),
                leading: icon == null
                    ? const Icon(Icons.apps)
                    : Image.memory(base64Decode(icon), width: 32, height: 32),
                title: Text(app['label']! as String),
                subtitle: Text(
                  '${enabled ? "On" : "Off"} · ${preset?.label ?? "Default: ${state.settings.defaultPreset.label}"}',
                ),
                trailing: Switch(
                  key: ValueKey('app-enabled-$pkg'),
                  value: enabled,
                  onChanged: state.changingRelay
                      ? null
                      : (value) => perform(
                          () => state.saveAppRule(pkg, value, preset),
                        ),
                ),
                onTap: () => editVibration(
                  context,
                  state,
                  title: app['label']! as String,
                  initial: preset,
                  onSave: (value) => state.saveAppRule(pkg, enabled, value),
                ),
              );
            },
          ),
        TextButton(
          key: const ValueKey('refresh-apps'),
          onPressed: () => perform(state.loadApps),
          child: const Text('Refresh app list'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Nearby notifications may be combined to give Google Health time to sync. A chosen chat wins over an app rule; the newest match wins ties.',
        ),
      ],
    );
  }
}

String formatMinute(BuildContext context, int minute) =>
    TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
Future<void> editQuietHours(
  BuildContext context,
  DemoController controller,
) async {
  var enabled = controller.settings.quietEnabled;
  var start = controller.settings.startMinute;
  var end = controller.settings.endMinute;
  var saving = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Quiet hours'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                key: const ValueKey('quiet-enabled'),
                title: const Text('Every day'),
                value: enabled,
                onChanged: saving ? null : (v) => update(() => enabled = v),
              ),
              for (final isStart in [true, false])
                ListTile(
                  title: Text(isStart ? 'From' : 'Until'),
                  trailing: Text(formatMinute(context, isStart ? start : end)),
                  onTap: saving
                      ? null
                      : () async {
                          final value = isStart ? start : end;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: value ~/ 60,
                              minute: value % 60,
                            ),
                          );
                          if (time != null && context.mounted) {
                            update(() {
                              if (isStart) {
                                start = time.hour * 60 + time.minute;
                              } else {
                                end = time.hour * 60 + time.minute;
                              }
                            });
                          }
                        },
                ),
              const Text(
                'Uses your phone’s local time. Overnight schedules are supported. Missed notifications are not replayed.',
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('save-quiet-hours'),
            onPressed: saving
                ? null
                : () async {
                    if (enabled && start == end) {
                      update(
                        () => error = 'Choose different start and end times.',
                      );
                      return;
                    }
                    update(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await controller.saveQuietHours(enabled, start, end);
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted) {
                        update(() {
                          saving = false;
                          error = 'Could not save. Try again.';
                        });
                      }
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
