import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

String timeLabel(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${t.day}/${t.month}';
}

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.onExplore});

  /// Switches to the Explore tab (used by the empty state).
  final VoidCallback onExplore;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String _query = '';
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;
    final all = app.conversations;
    final list = all.where((c) {
      if (_unreadOnly && c.unread == 0) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.profile.name.toLowerCase().contains(q) || c.messages.any((m) => m.text.toLowerCase().contains(q));
    }).toList();
    final online = all.where((c) => c.profile.online).map((c) => c.profile).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: ShaderMask(
                  shaderCallback: HuntrColors.accentGradient.createShader,
                  child: Text('Chats',
                      style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
            if (all.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('chatSearch'),
                    decoration: const InputDecoration(hintText: 'Search chats', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: !_unreadOnly,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _unreadOnly = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Unread${app.totalUnread > 0 ? ' (${app.totalUnread})' : ''}'),
                      selected: _unreadOnly,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _unreadOnly = true),
                    ),
                  ]),
                ),
              ),
              if (online.isNotEmpty && _query.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      itemCount: online.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (_, i) => InkWell(
                        borderRadius: BorderRadius.circular(40),
                        onTap: () => _open(context, online[i]),
                        child: Column(children: [
                          Avatar(profile: online[i], size: 54),
                          const SizedBox(height: 4),
                          Text(online[i].name, style: text.labelSmall),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
            if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyChats(onExplore: widget.onExplore),
              )
            else if (list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No chats match', style: TextStyle(color: HuntrColors.muted))),
              )
            else
              SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  final last = c.last!;
                  final unread = c.unread > 0;
                  return Dismissible(
                    key: ValueKey('conv-${c.profile.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: const Color(0xFF5A1D1D),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 6),
                        Text('Delete'),
                      ]),
                    ),
                    onDismissed: (_) {
                      app.deleteConversation(c.profile.id);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Chat with ${c.profile.name} deleted')));
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Avatar(profile: c.profile, size: 52),
                      title: Text(c.profile.name,
                          style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                      subtitle: Text(
                        c.typing ? 'typing…' : '${last.fromMe ? 'You: ' : ''}${last.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.typing ? HuntrColors.amber : (unread ? Colors.white : HuntrColors.muted),
                          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(timeLabel(last.sentAt, now),
                              style: text.labelSmall?.copyWith(color: unread ? HuntrColors.amber : HuntrColors.muted)),
                          const SizedBox(height: 6),
                          if (unread)
                            Badge(
                              label: Text('${c.unread}'),
                              backgroundColor: HuntrColors.amber,
                              textColor: Colors.black,
                            )
                          else if (last.fromMe)
                            Icon(last.status == MessageStatus.read ? Icons.done_all : Icons.done,
                                size: 16, color: last.status == MessageStatus.read ? HuntrColors.amber : HuntrColors.muted),
                        ],
                      ),
                      onTap: () => _open(context, c.profile),
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Profile p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(profileId: p.id)));
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.forum_outlined, size: 56, color: HuntrColors.muted),
          const SizedBox(height: 12),
          Text('No chats yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Say hi to someone nearby to start a conversation.',
              textAlign: TextAlign.center, style: TextStyle(color: HuntrColors.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onExplore, child: const Text('Explore people')),
        ],
      ),
    );
  }
}
