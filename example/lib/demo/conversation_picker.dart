import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_controller.dart';

class ConversationPicker extends StatefulWidget {
  const ConversationPicker({
    super.key,
    required this.controller,
    required this.perform,
  });
  final DemoController controller;
  final void Function(Future<void> Function()) perform;

  @override
  State<ConversationPicker> createState() => _ConversationPickerState();
}

class _ConversationPickerState extends State<ConversationPicker> {
  bool _showAll = false;

  void configure(String method, [Object? arguments]) => widget.perform(
    () => widget.controller.configureConversations(method, arguments),
  );

  Future<void> select(Map<String, Object?> chat, bool enabled) async {
    var allowNameMatch = false;
    if (enabled && chat['kind'] == 'name') {
      allowNameMatch =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Match this chat by name?'),
              content: const Text(
                'WhatsApp did not provide a conversation ID. This rule will match the exact notification chat name instead. Other chats with the same name can also vibrate. Renaming a chat can stop matching. For a group, everyone in that group is allowed.',
              ),
              actions: [
                TextButton(
                  key: const ValueKey('cancel-name-match'),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('confirm-name-match'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Use exact name'),
                ),
              ],
            ),
          ) ??
          false;
      if (!allowNameMatch) return;
    }
    await widget.controller.configureConversations('selectConversation', {
      'id': chat['id'],
      'enabled': enabled,
      'allowNameMatch': allowNameMatch,
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller;
    final blocked = state.relayRunning || state.changingRelay;
    final enabledApp = state.selectedApps.any(
      (app) => app == 'com.whatsapp' || app == 'com.whatsapp.w4b',
    );
    final allowedIds = state.allowedConversations
        .map((item) => item['id'])
        .toSet();
    final chats = [
      ...state.allowedConversations,
      ...state.conversationCandidates.where(
        (item) => !allowedIds.contains(item['id']),
      ),
    ];
    final capturing = state.captureRemainingMillis > 0;
    final stats = state.captureDiagnostics;
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: const ValueKey('conversation-picker'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.forum_outlined, color: colors.primary),
              title: const Text('Choose people'),
              subtitle: const Text('WhatsApp & WhatsApp Business'),
              trailing: allowedIds.isEmpty
                  ? null
                  : Chip(label: Text('${allowedIds.length} chosen')),
            ),
            SwitchListTile(
              key: const ValueKey('restrict-conversations'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Only selected WhatsApp chats'),
              subtitle: Text(
                state.restrictedConversations
                    ? 'Only checked chats can vibrate.'
                    : 'All chats can vibrate.',
              ),
              value: state.restrictedConversations,
              onChanged: blocked
                  ? null
                  : (value) =>
                        configure('restrictConversations', {'enabled': value}),
            ),
            if (blocked)
              const Text('Stop the relay to change people or find chats.')
            else if (!enabledApp)
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  key: const ValueKey('enable-whatsapp'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Enable WhatsApp notifications'),
                  onPressed: () => widget.perform(
                    () => state.selectApp('com.whatsapp', true),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text('Find a chat', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('Find unread chats, or listen for a new message.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('capture-conversations'),
              onPressed: blocked || !state.access || !state.listenerConnected
                  ? null
                  : () => configure('captureConversations', {
                      'enabled': !capturing,
                    }),
              icon: Icon(
                capturing
                    ? Icons.stop_circle_outlined
                    : Icons.person_search_outlined,
              ),
              label: Text(capturing ? 'Stop listening' : 'Find chats'),
            ),
            if (!state.access || !state.listenerConnected)
              TextButton(
                onPressed: state.openAccessSettings,
                child: const Text('Enable notification access to find chats'),
              ),
            if (capturing) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: state.captureRemainingMillis / 60000,
              ),
              const SizedBox(height: 6),
              Text(
                'Listening · ${(state.captureRemainingMillis / 1000).ceil()} s left. Results stay available for 5 minutes.',
              ),
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                key: const ValueKey('capture-diagnostics'),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_diagnosticMessage(stats, chats.length)),
                ),
              ),
            ] else if (capturing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No WhatsApp notification received yet. Keep the chat closed and check that WhatsApp notifications are enabled.',
                ),
              ),
            if (state.restrictedConversations && allowedIds.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Choose a chat below. WhatsApp stays silent until then.',
                ),
              ),
            if (chats.isNotEmpty) ...[
              const Divider(height: 24),
              for (final chat in chats.take(_showAll ? 96 : 8))
                CheckboxListTile(
                  key: ValueKey('conversation-${chat['id']}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(chat['label']! as String),
                  subtitle: Text(
                    '${chat['packageName'] == 'com.whatsapp.w4b' ? 'Business · ' : ''}${chat['kind'] == 'name' ? 'Match by name · review' : 'Match by conversation ID'}',
                  ),
                  value: allowedIds.contains(chat['id']),
                  onChanged: blocked
                      ? null
                      : (value) => widget.perform(() => select(chat, value!)),
                ),
              if (chats.length > 8)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                    _showAll ? 'Show fewer' : 'Show all ${chats.length} chats',
                  ),
                ),
            ],
            if (stats.isNotEmpty)
              ExpansionTile(
                key: const ValueKey('capture-details'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Troubleshooting'),
                subtitle: Text(
                  '${stats['seen'] ?? 0} notifications seen · ${stats['missingId'] ?? 0} without ID',
                ),
                children: [
                  Text(
                    'Unread snapshot: ${stats['existing'] ?? 0} · Summaries: ${stats['summary'] ?? 0} · Ongoing: ${stats['ongoing'] ?? 0} · Unusable: ${stats['unusable'] ?? 0} · Errors: ${stats['errors'] ?? 0}',
                  ),
                  TextButton.icon(
                    key: const ValueKey('copy-capture-report'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: state.exportJson()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sanitized report copied'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy sanitized debug report'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              'Direct chats: one person. Groups: everyone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (chats.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('clear-conversations'),
                  onPressed: blocked
                      ? null
                      : () => configure('clearConversations'),
                  child: const Text('Forget chats'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _diagnosticMessage(Map<String, int> stats, int chats) {
    if ((stats['errors'] ?? 0) > 0) {
      return 'Android could not expose some notification metadata. Try reconnecting notification access. Captured chats are shown below.';
    }
    if ((stats['nameOnly'] ?? 0) > 0) {
      return 'Found chat names without IDs. Select one below to review name matching.';
    }
    if (chats > 0) {
      return 'Chats found. Select who may vibrate, then start the relay.';
    }
    if ((stats['seen'] ?? 0) == 0) {
      return 'No WhatsApp notifications found. Leave a message unread and try again, or check notification access.';
    }
    if ((stats['unusable'] ?? 0) > 0) {
      return 'WhatsApp notifications arrived without usable chat metadata. Check WhatsApp notification privacy settings and try a direct message.';
    }
    return 'Only summary or ongoing notifications were found. Open WhatsApp, leave the chat, then receive a new message.';
  }
}
