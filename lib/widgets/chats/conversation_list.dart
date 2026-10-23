import 'package:flutter/material.dart';

import '../../screens/chat_screen.dart';
import '../../screens/chats_screen.dart' show timeLabel;
import '../../services/huntr_backend.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import '../load_more_row.dart';
import '../pill_tabs.dart';
import '../anonymous_avatar.dart';
import '../avatar.dart';
import '../me/section_states.dart';
import '../profile_tile.dart' show NewBadge;
import 'empty_chats.dart';

/// My conversations from the backend, newest activity first, with the last
/// message and unread count, in two tabs: Direct, and Anonymous (anonymous
/// conversations, both ways). Live events and syncs update it.
class ConversationList extends StatefulWidget {
  const ConversationList(
      {super.key, required this.messaging, required this.onExplore});

  final MessagingState messaging;
  final VoidCallback onExplore;

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  String _query = '';
  bool _unreadOnly = false;

  /// The Anonymous tab is shown (otherwise Direct).
  bool _anonymous = false;

  /// Wide screens: the conversation open on the right.
  int? _selected;

  /// The list beside an open chat, from this width on.
  static const _twoPaneWidth = 900.0;
  static const _listWidth = 380.0;

  @override
  Widget build(BuildContext context) {
    final messaging = widget.messaging;
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;
    final all =
        _anonymous ? messaging.anonymousConversations : messaging.conversations;
    final loadError =
        _anonymous ? messaging.anonymousLoadError : messaging.loadError;
    final unreadTotal =
        _anonymous ? messaging.anonymousUnread : messaging.directUnread;
    final more = messaging.hasMore(anonymous: _anonymous);
    final loadMore = LoadMoreRow(
      // a new one per page, so each end asks again
      key: ValueKey('more-$_anonymous-${all?.length}'),
      onVisible: () => messaging.loadMore(anonymous: _anonymous),
    );
    final list = (all ?? const []).where((c) {
      if (_unreadOnly && c.unreadCount == 0) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.other.name.toLowerCase().contains(q) ||
          (c.lastMessage?.body.toLowerCase().contains(q) ?? false);
    }).toList();

    // Wide screens: the list on the left, the open chat on the right.
    final width = MediaQuery.sizeOf(context).width;
    final twoPane = width >= _twoPaneWidth;
    final side = twoPane
        ? 12.0
        : width > 752
            ? (width - 720) / 2
            : 16.0;
    EdgeInsets pad(double top, double bottom) =>
        EdgeInsets.fromLTRB(side, top, side, bottom);
    final selected =
        twoPane && _selected != null ? messaging.summary(_selected!) : null;

    void open(ConversationSummary c) {
      if (twoPane) {
        setState(() => _selected = c.id);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              ChatScreen.conversation(conversationId: c.id, other: c.other)));
    }

    final listPane = Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: HuntrColors.orange,
          onRefresh: messaging.sync,
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: pad(12, 12),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ShaderMask(
                    shaderCallback: HuntrColors.accentGradient.createShader,
                    child: Text('Chats',
                        style: text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ),
            ),
            // ---- Direct / Anonymous ----
            SliverPadding(
              padding: pad(0, 12),
              sliver: SliverToBoxAdapter(
                child: _Tabs(
                  anonymous: _anonymous,
                  directUnread: messaging.directUnread,
                  anonymousUnread: messaging.anonymousUnread,
                  onChanged: (anonymous) => setState(() {
                    _anonymous = anonymous;
                    _unreadOnly = false;
                  }),
                ),
              ),
            ),
            SliverPadding(
              padding: pad(0, 12),
              sliver: SliverToBoxAdapter(
                child: Wrap(spacing: 8, children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !_unreadOnly,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _unreadOnly = false),
                  ),
                  ChoiceChip(
                    key: const Key('unreadChats'),
                    label: Text(
                        'Unread${unreadTotal > 0 ? ' ($unreadTotal)' : ''}'),
                    selected: _unreadOnly,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _unreadOnly = true),
                  ),
                ]),
              ),
            ),
            if (all == null && loadError != null)
              SliverPadding(
                padding: pad(4, 16),
                sliver: SliverToBoxAdapter(
                  child: LoadFailedCard(
                    title: "Couldn't load your chats",
                    message: loadError,
                    onRetry: messaging.refresh,
                    retryKey: const Key('chatsRetry'),
                  ),
                ),
              )
            else if (all == null)
              SliverPadding(
                padding: pad(4, 16),
                sliver: const SliverToBoxAdapter(
                    child: LoadingRows(count: 4, height: 72)),
              )
            else if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _anonymous
                    ? const _NoAnonymousChats()
                    : EmptyChats(onExplore: widget.onExplore),
              )
            else ...[
              SliverPadding(
                padding: pad(0, 8),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    key: const Key('chatSearch'),
                    decoration: const InputDecoration(
                        hintText: 'Search chats',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              // nothing matches among those loaded: look further
              if (list.isEmpty && more)
                SliverToBoxAdapter(child: loadMore)
              else if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          _unreadOnly && _query.isEmpty
                              ? Icons.mark_chat_read_outlined
                              : Icons.search_off_rounded,
                          size: 40,
                          color: HuntrColors.muted),
                      const SizedBox(height: 10),
                      Text(
                          _unreadOnly && _query.isEmpty
                              ? "You're all caught up"
                              : 'No chats match',
                          style: const TextStyle(color: HuntrColors.muted)),
                    ]),
                  ),
                )
              else
                SliverPadding(
                  // rows reach a little past the column so their text lines
                  // up with the search box
                  padding: EdgeInsets.symmetric(horizontal: side - 8),
                  sliver: SliverList.builder(
                    // and, while there's more, a last row that loads the
                    // next page when it's reached (built only then)
                    itemCount: list.length + (more ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == list.length) return loadMore;
                      final c = list[i];
                      return _ConversationRow(
                        conversation: c,
                        now: now,
                        typing: messaging.isTyping(c.id),
                        selected: c.id == selected?.id,
                        onTap: () => open(c),
                      );
                    },
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      ),
    );
    if (!twoPane) return listPane;
    return Row(children: [
      SizedBox(width: _listWidth, child: listPane),
      const VerticalDivider(width: 1, color: HuntrColors.border),
      Expanded(
        child: selected == null
            ? const _NoChatOpen()
            // a new chat screen per conversation (its own state and session)
            : ChatScreen.conversation(
                key: ValueKey('chat-${selected.id}'),
                conversationId: selected.id,
                other: selected.other,
                onClose: () => setState(() => _selected = null)),
      ),
    ]);
  }
}

/// Direct and Anonymous, each with its unread count.
class _Tabs extends StatelessWidget {
  const _Tabs(
      {required this.anonymous,
      required this.directUnread,
      required this.anonymousUnread,
      required this.onChanged});

  final bool anonymous;
  final int directUnread;
  final int anonymousUnread;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => PillTabs(
        selected: anonymous ? 1 : 0,
        onChanged: (i) => onChanged(i == 1),
        tabs: [
          PillTab(
              key: const Key('directTab'),
              icon: Icons.forum_outlined,
              label: 'Direct',
              badge: directUnread),
          PillTab(
              key: const Key('anonymousTab'),
              icon: Icons.theater_comedy_outlined,
              label: 'Anonymous',
              badge: anonymousUnread),
        ],
      );
}

/// The Anonymous tab, empty.
class _NoAnonymousChats extends StatelessWidget {
  const _NoAnonymousChats();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('noAnonymousChats'),
      padding: EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 80,
            height: 80,
            child: AnonymousArt(animal: 'fox', radius: 40, size: 80)),
        SizedBox(height: 18),
        Text('No anonymous chats yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text(
            'Anonymous messages you send or receive show up here. '
            'Nobody sees who sent them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: HuntrColors.muted)),
      ]),
    );
  }
}

/// Wide screens, before a chat is chosen.
class _NoChatOpen extends StatelessWidget {
  const _NoChatOpen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: HuntrColors.night,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, size: 56, color: HuntrColors.muted),
          SizedBox(height: 14),
          Text('Choose a chat',
              key: Key('noChatOpen'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Your conversations open here.',
              style: TextStyle(color: HuntrColors.muted)),
        ]),
      ),
    );
  }
}

/// In a conversation where I'm the anonymous one: whom they see.
class _MaskBadge extends StatelessWidget {
  const _MaskBadge({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        key: const Key('maskBadge'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: HuntrColors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.theater_comedy_outlined,
              size: 13, color: HuntrColors.orange),
          const SizedBox(width: 4),
          Flexible(
            child: Text('as $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: HuntrColors.orange)),
          ),
        ]),
      ),
    );
  }
}

/// One conversation: photo, name, last message, time and unread count.
/// Unread ones stand out with a warm tint and a bold preview.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow(
      {required this.conversation,
      required this.now,
      required this.onTap,
      this.selected = false,
      this.typing = false});

  final ConversationSummary conversation;
  final DateTime now;
  final VoidCallback onTap;

  /// They're typing in this chat right now: shown instead of the preview.
  final bool typing;

  /// Open on the right (wide screens).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final last = c.lastMessage;
    final unread = c.unreadCount > 0;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? HuntrColors.surfaceHigh
            : unread
                ? HuntrColors.orange.withValues(alpha: 0.07)
                : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: selected
                  ? HuntrColors.orange.withValues(alpha: 0.5)
                  : unread
                      ? HuntrColors.orange.withValues(alpha: 0.22)
                      : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('conversation-${c.id}'),
          onTap: onTap,
          hoverColor: HuntrColors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
            child: Row(children: [
              // where I'm the anonymous one: a mask over their picture
              c.anonymous?.iAmAnonymous == true
                  ? MaskOverlay(
                      size: 56,
                      online: c.other.online,
                      child:
                          Avatar(profile: c.other, size: 56, showOnline: false))
                  : Avatar(profile: c.other, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Row(children: [
                          Flexible(
                            child: Text(c.other.nameAndAge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: unread
                                        ? FontWeight.w800
                                        : FontWeight.w700)),
                          ),
                          if (c.other.isNew && c.anonymous == null) ...[
                            const SizedBox(width: 8),
                            const NewBadge(),
                          ],
                          // where I'm the anonymous one: whom they see
                          if (c.anonymous case final a?
                              when a.iAmAnonymous) ...[
                            const SizedBox(width: 8),
                            _MaskBadge(name: a.name),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 8),
                      if (last != null)
                        Text(timeLabel(last.sentAt, now),
                            style: text.labelSmall?.copyWith(
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w500,
                                color: unread
                                    ? HuntrColors.orange
                                    : HuntrColors.muted)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (!typing && last != null && last.fromMe)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: last.read
                              ? Icon(Icons.done_all_rounded,
                                  key: Key('lastRead'),
                                  size: 16,
                                  color: HuntrColors.orange)
                              : const Icon(Icons.done_rounded,
                                  size: 16, color: HuntrColors.muted),
                        ),
                      Expanded(
                        child: Text(
                          typing
                              ? 'typing…'
                              : last == null
                                  ? 'Say hi 👋'
                                  : '${last.fromMe ? 'You: ' : ''}${last.preview}',
                          key: typing ? Key('typingRow-${c.id}') : null,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: typing
                                ? HuntrColors.orange
                                : unread
                                    ? Colors.white
                                    : HuntrColors.muted,
                            fontWeight: typing || unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 10),
                        Container(
                          key: Key('unread-${c.id}'),
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              gradient: HuntrColors.accentGradient,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(11))),
                          child: Text(
                              c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
