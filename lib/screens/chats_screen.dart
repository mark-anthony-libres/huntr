import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import '../widgets/chats/empty_chats.dart';
import '../flows/accept_with_album.dart';
import '../state/messaging_state.dart';
import '../widgets/chats/conversation_list.dart';

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
  bool _showRequests = false;

  @override
  Widget build(BuildContext context) {
    // with the backend: my real conversations (no requests)
    final messaging = MessagingScope.of(context);
    if (messaging != null) {
      return ConversationList(
          messaging: messaging, onExplore: widget.onExplore);
    }
    final app = AppScope.of(context);
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;
    final all = app.conversations;
    final list = all.where((c) {
      if (_unreadOnly && c.unread == 0) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.profile.name.toLowerCase().contains(q) ||
          c.messages.any((m) => m.text.toLowerCase().contains(q));
    }).toList();
    final online =
        all.where((c) => c.profile.online).map((c) => c.profile).toList();
    final incoming = app.incomingRequests;
    final outgoing = app.outgoingRequests;

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
                      style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !_unreadOnly && !_showRequests,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _unreadOnly = false;
                      _showRequests = false;
                    }),
                  ),
                  ChoiceChip(
                    label: Text(
                        'Unread${app.totalUnread > 0 ? ' (${app.totalUnread})' : ''}'),
                    selected: _unreadOnly && !_showRequests,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _unreadOnly = true;
                      _showRequests = false;
                    }),
                  ),
                  ChoiceChip(
                    key: const Key('requestsTab'),
                    avatar: incoming.isEmpty
                        ? null
                        : const Icon(Icons.circle,
                            size: 10, color: HuntrColors.orange),
                    label: Text(
                        'Requests${incoming.isNotEmpty ? ' (${incoming.length})' : ''}'),
                    selected: _showRequests,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _showRequests = true),
                  ),
                ]),
              ),
            ),
            if (_showRequests)
              ..._requestSlivers(context, app, incoming, outgoing, now)
            else ...[
              if (all.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      key: const Key('chatSearch'),
                      decoration: const InputDecoration(
                          hintText: 'Search chats',
                          prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => _query = v),
                    ),
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
                  child: EmptyChats(onExplore: widget.onExplore),
                )
              else if (list.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child: Text('No chats match',
                          style: TextStyle(color: HuntrColors.muted))),
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
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline),
                              SizedBox(width: 6),
                              Text('Delete'),
                            ]),
                      ),
                      onDismissed: (_) {
                        app.deleteConversation(c.profile.id);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text('Chat with ${c.profile.name} deleted')));
                      },
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Avatar(profile: c.profile, size: 52),
                        title: Text(c.profile.name,
                            style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600)),
                        subtitle: Text(
                          c.typing
                              ? 'typing…'
                              : switch (last.kind) {
                                  MessageKind.album => '📷 ${last.text}',
                                  MessageKind.notice => last.text,
                                  MessageKind.text =>
                                    '${last.fromMe ? 'You: ' : ''}${last.text}',
                                },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.typing
                                ? HuntrColors.orange
                                : (unread ? Colors.white : HuntrColors.muted),
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(timeLabel(last.sentAt, now),
                                style: text.labelSmall?.copyWith(
                                    color: unread
                                        ? HuntrColors.orange
                                        : HuntrColors.muted)),
                            const SizedBox(height: 6),
                            if (unread)
                              Badge(
                                label: Text('${c.unread}'),
                                backgroundColor: HuntrColors.orange,
                                textColor: Colors.black,
                              )
                            else if (last.fromMe)
                              Icon(
                                  last.status == MessageStatus.read
                                      ? Icons.done_all
                                      : Icons.done,
                                  size: 16,
                                  color: last.status == MessageStatus.read
                                      ? HuntrColors.orange
                                      : HuntrColors.muted),
                          ],
                        ),
                        onTap: () => _open(context, c.profile),
                      ),
                    );
                  },
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _requestSlivers(BuildContext context, AppState app,
      List<ChatRequest> incoming, List<ChatRequest> outgoing, DateTime now) {
    final text = Theme.of(context).textTheme;
    Widget header(String s) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(s.toUpperCase(),
                style: text.labelMedium
                    ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
          ),
        );
    if (incoming.isEmpty && outgoing.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.all(32),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.mark_chat_unread_outlined,
                  size: 56, color: HuntrColors.muted),
              SizedBox(height: 12),
              Text('No requests right now'),
              SizedBox(height: 4),
              Text('When someone wants to chat, it shows up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HuntrColors.muted)),
            ]),
          ),
        ),
      ];
    }
    return [
      if (incoming.isNotEmpty) ...[
        header('Wants to chat with you'),
        SliverList.builder(
          itemCount: incoming.length,
          itemBuilder: (_, i) {
            final r = incoming[i];
            final p = app.profileById(r.profileId)!;
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: HuntrColors.surface,
                  borderRadius: BorderRadius.circular(18)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _openProfile(context, p),
                      child: Row(children: [
                        Avatar(profile: p, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.nameAndAge,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    '${p.distanceLabel} · ${timeLabel(r.sentAt, now)} ago',
                                    style: const TextStyle(
                                        color: HuntrColors.muted,
                                        fontSize: 12.5)),
                              ]),
                        ),
                        const Icon(Icons.chevron_right,
                            color: HuntrColors.muted),
                      ]),
                    ),
                    if (r.note != null) ...[
                      const SizedBox(height: 10),
                      Text('"${r.note}"',
                          style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => app.declineRequest(p.id),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          key: Key('accept-${p.id}'),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Accept'),
                          onPressed: () => acceptWithAlbum(context, p),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        p.albumById(r.albumId) == null
                            ? 'You choose which album to send when you accept.'
                            : 'Sends you "${p.albumById(r.albumId)!.name}". You choose which album to send back.',
                        style:
                            TextStyle(color: HuntrColors.muted, fontSize: 12)),
                  ]),
            );
          },
        ),
      ],
      if (outgoing.isNotEmpty) ...[
        header('Sent · waiting for a reply'),
        SliverList.builder(
          itemCount: outgoing.length,
          itemBuilder: (_, i) {
            final p = app.profileById(outgoing[i].profileId)!;
            return ListTile(
              leading: Avatar(profile: p, size: 44),
              title: Text(p.name),
              subtitle: Text('Sent ${timeLabel(outgoing[i].sentAt, now)} ago',
                  style: const TextStyle(color: HuntrColors.muted)),
              trailing: TextButton(
                  onPressed: () => app.cancelRequest(p.id),
                  child: const Text('Cancel')),
              onTap: () => _openProfile(context, p),
            );
          },
        ),
      ],
    ];
  }

  void _openProfile(BuildContext context, Profile p) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(profileId: p.id)));
  }

  void _open(BuildContext context, Profile p) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(profileId: p.id)));
  }
}
