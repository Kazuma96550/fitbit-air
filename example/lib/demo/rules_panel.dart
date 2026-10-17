import 'dart:convert';
import 'package:flutter/material.dart';
import 'demo_controller.dart';
import 'conversation_picker.dart';
import 'relay_settings.dart';

Future<void> editVibration(
  BuildContext context,
  DemoController controller, {
  required String title,
  required VibrationPreset? initial,
  required Future<void> Function(VibrationPreset?) onSave,
  bool allowDefault = true,
  bool allowMute = false,
  VibrationPreset? inheritedPreset,
  String inheritLabel = 'Use default vibration',
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _VibrationEditor(
    controller: controller,
    title: title,
    initial: initial,
    onSave: onSave,
    allowDefault: allowDefault,
    allowMute: allowMute,
    inheritedPreset: inheritedPreset,
    inheritLabel: inheritLabel,
  ),
);

class _VibrationEditor extends StatefulWidget {
  const _VibrationEditor({
    required this.controller,
    required this.title,
    required this.initial,
    required this.onSave,
    required this.allowDefault,
    required this.allowMute,
    required this.inheritedPreset,
    required this.inheritLabel,
  });
  final DemoController controller;
  final String title;
  final VibrationPreset? initial;
  final Future<void> Function(VibrationPreset?) onSave;
  final bool allowDefault, allowMute;
  final VibrationPreset? inheritedPreset;
  final String inheritLabel;
  @override
  State<_VibrationEditor> createState() => _VibrationEditorState();
}

class _VibrationEditorState extends State<_VibrationEditor> {
  late VibrationPreset? selected = widget.initial;
  bool working = false;
  String? error;
  String? feedback;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> run(Future<void> Function() action, {bool save = false}) async {
    setState(() {
      working = true;
      error = null;
      feedback = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (save) {
        Navigator.pop(context);
        return;
      }
      setState(() => feedback = 'Command verified. Did you feel it?');
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not complete this action. Check your Air and relay status, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inherited =
        widget.inheritedPreset ?? widget.controller.settings.defaultPreset;
    final effective = selected ?? inherited;
    return FractionallySizedBox(
      heightFactor: .9,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: working ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Choose a vibration. Trying it does not save changes.'),
          if (widget.allowDefault)
            ListTile(
              key: const ValueKey('preset-default'),
              title: Text(widget.inheritLabel),
              subtitle: Text(inherited.label),
              leading: Icon(
                selected == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: working ? null : () => setState(() => selected = null),
            ),
          for (final preset in VibrationPreset.values.where(
            (p) => widget.allowMute || p != VibrationPreset.mute,
          ))
            ListTile(
              key: ValueKey('preset-${preset.id}'),
              title: Text(preset.label),
              subtitle: Text(preset.description),
              leading: Icon(
                selected == preset
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: working ? null : () => setState(() => selected = preset),
            ),
          if (effective.intensity != null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Low and high change the band’s vibration strength. It keeps that strength afterward, including for other apps.',
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('preview-rule'),
            onPressed:
                working ||
                    widget.controller.busy ||
                    widget.controller.previewing ||
                    widget.controller.changingRelay ||
                    (widget.controller.relayRunning &&
                        widget.controller.settings.silenceReason != null) ||
                    effective == VibrationPreset.mute
                ? null
                : () => run(() => widget.controller.previewPreset(effective)),
            icon: working
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.vibration),
            label: Text(working ? 'Working…' : 'Try this vibration'),
          ),
          if (widget.controller.relayRunning &&
              widget.controller.settings.silenceReason != null)
            const Text(
              'Resume notifications or leave quiet hours before trying a vibration.',
            ),
          if (feedback != null)
            Semantics(liveRegion: true, child: Text(feedback!)),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('save-rule'),
            onPressed: working
                ? null
                : () => run(() => widget.onSave(selected), save: true),
            child: const Text('Save'),
          ),
          if (widget.allowMute)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Use app default removes the custom override. Selected-chat restrictions still apply.',
              ),
            ),
          SizedBox(height: MediaQuery.viewInsetsOf(context).bottom + 16),
        ],
      ),
    );
  }
}

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
                  ? '${formatMinute(context, state.settings.startMinute)} – ${formatMinute(context, state.settings.endMinute)} · Every day'
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
        const SizedBox(height: 20),
        Text('WhatsApp people', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Choose all chats or selected chats below. A chat vibration overrides its app’s vibration; a silent chat never vibrates.',
        ),
        const SizedBox(height: 12),
        ConversationPicker(controller: state, perform: perform),
        for (final chat in state.allowedConversations)
          ListTile(
            key: ValueKey('chat-rule-${chat['id']}'),
            title: Text(chat['label']! as String),
            subtitle: Text(
              state.settings.chats[chat['id']]?.label ?? 'Uses app vibration',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => editVibration(
              context,
              state,
              title: chat['label']! as String,
              initial: state.settings.chats[chat['id']],
              allowMute: true,
              inheritLabel: 'Use app vibration',
              inheritedPreset:
                  state.settings.apps[chat['packageName']]?.preset ??
                  state.settings.defaultPreset,
              onSave: (value) =>
                  state.saveChatRule(chat['id']! as String, value),
            ),
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
