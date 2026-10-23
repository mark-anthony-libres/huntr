import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/sample_data.dart';
import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/anonymous_avatar.dart';
import '../widgets/avatar.dart';
import 'profile_screen.dart';
import '../widgets/chat/tap_card.dart';
import '../widgets/chat/chat_intro.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/chat_notice.dart';
import '../widgets/chat/album_bubble.dart';
import '../widgets/chat/time_divider.dart';
import '../widgets/chat/typing_bubble.dart';
import '../widgets/me/section_states.dart';
import '../flows/chat_attachments.dart';
import '../flows/open_person_profile.dart';
import '../widgets/chat/gif_bubble.dart';
import '../widgets/chat/story_reply_label.dart';
import '../widgets/chat/gif_picker.dart';
import '../widgets/chat/media_bubble.dart';
import '../widgets/chat/trade_card.dart';
import 'chat_media_viewer_screen.dart';
import 'traded_album_viewer_screen.dart';
import 'location_map_screen.dart';
import 'live_location_screen.dart';
import '../widgets/chat/live_location_card.dart';
import '../widgets/chat/reactions.dart';
import '../widgets/chat/reply.dart';
import '../state/block_state.dart';
import '../widgets/block_gate.dart';
import '../widgets/chat/location_bubble.dart';
import 'my_album_screen.dart';
import 'story_viewer_screen.dart';
import 'anonymous_profile_screen.dart';
import '../widgets/chat/anonymous_chat.dart';
import '../flows/my_albums.dart';

class ChatScreen extends StatefulWidget {
  /// A sample chat (no backend), by profile.
  const ChatScreen({super.key, required String this.profileId})
      : conversationId = null,
        other = null,
        onClose = null;

  /// A direct-message conversation on the backend, with that person.
  const ChatScreen.conversation(
      {super.key,
      required int this.conversationId,
      required Profile this.other,
      this.onClose})
      : profileId = null;

  final String? profileId;
  final int? conversationId;
  final Profile? other;

  /// Shown beside the chat list (wide screens): Back (and Esc) closes it
  /// here instead of leaving a page.
  final VoidCallback? onClose;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AppState? _appRef;
  AppState get _app => _appRef!;
  MessagingState? _messaging;

  int? get _conversationId => widget.conversationId;

  /// Keeps countdowns current, and expired photos shown as expired.
  Timer? _clock;

  /// Trades being cancelled or declined (their buttons wait).
  final Set<int> _changingTrades = {};

  /// Previews already re-fetched once (their link had expired).
  final Set<int> _refreshedPreviews = {};

  void _refreshPreview(ChatMessage m) {
    if (m.id == null || !_refreshedPreviews.add(m.id!)) return;
    _messaging?.refreshMessage(m.conversationId, m.id!);
  }

  /// My profile photos (for my pin on shared locations), if Me hasn't
  /// loaded them yet.
  Future<void> _loadMyPhotos() async {
    final app = _app;
    final photos = ServicesScope.photosOf(context);
    final token = app.sessionToken;
    if (app.profilePhotos.isNotEmpty || photos == null || token == null) return;
    try {
      final list = await photos.fetchMine(token);
      app.setProfilePhotos(list.photos, maxPhotos: list.maxPhotos);
    } catch (error) {
      debugPrint('My photos could not be loaded: $error');
    }
  }

  /// One of my albums from a trade card: my album screen (my albums are
  /// loaded first if they aren't yet).
  /// A story reply's story: theirs (I replied) or mine (they did), from
  /// that story; then the reply again (the story may have gone meanwhile).
  Future<void> _openStory(ChatMessage m, Profile other) async {
    final service = ServicesScope.storiesOf(context);
    if (service == null || m.storyId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => m.fromMe
            ? StoryViewerScreen(
                service: service, people: [other], startStoryId: m.storyId)
            : StoryViewerScreen.mine(
                service: service,
                me: _app.myPublicProfile,
                startStoryId: m.storyId)));
    if (mounted && m.id != null) {
      unawaited(MessagingScope.read(context)!
          .refreshMessage(m.conversationId, m.id!));
    }
  }

  Future<void> _openMyAlbum(int albumId) async {
    final app = _app;
    final token = app.sessionToken;
    if (app.myAlbumById('$albumId') == null &&
        token != null &&
        ServicesScope.albumsOf(context) != null) {
      try {
        await MyAlbums.of(context).load(token);
      } catch (error) {
        debugPrint('Albums could not be loaded: $error');
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MyAlbumScreen(albumId: '$albumId')));
  }

  Future<void> _cancelTrade(ChatMessage m) async {
    final trade = m.trade!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(trade.fromMe ? 'Cancel this offer?' : 'Decline this trade?'),
        content: Text(trade.fromMe
            ? 'The trade can’t be completed after that.'
            : 'This declines the trade. It can’t be completed after that.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it')),
          TextButton(
              key: const Key('confirmCancelTrade'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(trade.fromMe ? 'Cancel offer' : 'Decline')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _changingTrades.add(trade.id));
    try {
      await _messaging?.cancelTrade(m.conversationId, trade);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is BackendException
                ? error.message
                : 'Check your connection and try again.')));
      }
    } finally {
      if (mounted) setState(() => _changingTrades.remove(trade.id));
    }
  }

  // ---- replies ----

  final _inputFocus = FocusNode();

  /// The message just jumped to from a reply's quote (briefly marked).
  int? _highlight;
  Timer? _unhighlight;

  /// Each message's place in the list, to find it again (a reply's quote).
  final Map<Object, GlobalKey> _itemKeys = {};

  GlobalKey _keyFor(ChatMessage m) =>
      _itemKeys.putIfAbsent(m.id ?? m.clientId ?? m, GlobalKey.new);

  ChatMessage? _replyingTo() {
    final id = _conversationId;
    return id == null ? null : MessagingScope.of(context)?.replyingTo(id);
  }

  void _startReply(ChatMessage m) {
    final id = _conversationId;
    if (id == null || m.id == null) return;
    _messaging?.setReplyingTo(id, m);
    _inputFocus.requestFocus();
  }

  void _cancelReply() {
    final id = _conversationId;
    if (id != null) _messaging?.setReplyingTo(id, null);
  }

  /// Any message's reply button, swipe and quote (cards included; only
  /// text, photos and videos take reactions).
  Widget _actions(ChatMessage m, Profile p, Widget child) => Reactable(
        message: m,
        enabled: !(_blockWith(p)?.blocked ?? false),
        onReact: (e) => _react(m, e),
        onReply: () => _startReply(m),
        otherName: p.name,
        onQuoteTap: _jumpTo,
        highlighted: _highlight == m.id,
        child: child,
      );

  /// A reply's quote was tapped: the message it shows, scrolled into view
  /// (older pages loaded until it's there) and briefly marked.
  Future<void> _jumpTo(int messageId) async {
    final id = _conversationId;
    final messaging = _messaging;
    if (id == null || messaging == null) return;
    bool loaded() => messaging.messagesOf(id).any((m) => m.id == messageId);
    for (var tries = 0; !loaded() && messaging.hasOlder(id) && tries < 100;) {
      final before = messaging.messagesOf(id).length;
      await messaging.loadOlder(id, retry: true);
      if (messaging.messagesOf(id).length == before) {
        tries++; // a page is still loading (or it failed): wait a little
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
    }
    if (!loaded()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That message isn\u2019t available any more.')));
      }
      return;
    }
    // the list only builds what's near the screen: move up until it is
    for (var step = 0; step < 200 && mounted; step++) {
      await WidgetsBinding.instance.endOfFrame;
      final target = _itemKeys[messageId]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(target,
            alignment: 0.4,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
        break;
      }
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      // reversed list: older messages are further along
      _scroll.jumpTo((position.pixels + position.viewportDimension * 0.8)
          .clamp(0.0, position.maxScrollExtent));
    }
    if (!mounted) return;
    setState(() => _highlight = messageId);
    _unhighlight?.cancel();
    _unhighlight = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  /// Accept / decline / cancel / stop a live location session; says what
  /// went wrong (e.g. it already ended).
  Future<void> _liveAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is BackendException
                ? error.message
                : 'Check your connection and try again.')));
      }
    }
  }

  /// My reaction on a message (the same one again removes it).
  void _react(ChatMessage m, String emoji) =>
      _liveAction(() => MessagingScope.read(context)!.react(m, emoji));

  void _openLive(ChatMessage m, Profile other) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LiveLocationScreen(
              message: m, me: _app.myPublicProfile, other: other)));

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      setState(() {});
      // tell the other person I'm typing (or stopped)
      final id = _conversationId;
      if (id != null) {
        _messaging?.notifyTyping(id, _input.text.trim().isNotEmpty);
      }
    });
    // near the top of the history (the list is reversed): load older ones
    _scroll.addListener(() {
      final id = _conversationId;
      if (id != null &&
          _scroll.hasClients &&
          _scroll.position.extentAfter < 300) {
        _messaging?.loadOlder(id);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appRef != null) {
      return; // runs again on every app-state change; set up only once
    }
    _appRef = AppScope.read(context);
    final id = _conversationId;
    if (id != null) {
      _messaging = MessagingScope.read(context);
      // after this frame: marking it read updates the list being built
      _clock = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadMyPhotos();
        _messaging
          ?..setViewing(id)
          ..load(id);
        // checked again every time the chat opens
        final other = widget.other?.backendId;
        if (other != null) BlockScope.read(context)?.check(other);
      });
    } else {
      _app.setOpenChat(widget.profileId);
    }
    // a notice floating over the message box would block the first tap on Send
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    final id = _conversationId;
    if (id != null) _messaging?.notifyTyping(id, false);
    if (_conversationId != null) {
      _messaging?.setViewing(null);
    } else {
      _app.setOpenChat(null);
    }
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    _unhighlight?.cancel();
    super.dispose();
  }

  void _send(Profile p, String text) {
    if (text.trim().isEmpty) return;
    final id = _conversationId;
    if (id != null) {
      _messaging?.send(id, p, text);
    } else {
      _app.send(p, text);
    }
    _input.clear();
    _scrollToNewest();
  }

  /// The GIF picker (GIFs and stickers); the one picked is sent at once.
  Future<void> _pickGif(Profile p) async {
    final id = _conversationId;
    if (id == null) return;
    final gif = await showGifPicker(context);
    if (gif == null || !mounted) return;
    _messaging?.sendGif(id, p, gif);
    _scrollToNewest();
  }

  /// After I send something: down to it, once it's in the list.
  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_conversationId != null) return _buildConversation(context);
    final app = AppScope.of(context);
    final p = app.profileById(widget.profileId!);
    if (p == null) {
      return const Scaffold(body: Center(child: Text('This chat has ended.')));
    }
    final c = app.conversationWith(p);
    final now = DateTime.now();
    final msgs = c.messages.reversed.toList();
    final connected = app.canChat(p.id);
    if (c.unread > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => app.markRead(p));
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProfileScreen(profileId: p.id))),
          child: Row(children: [
            Avatar(profile: p, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      c.typing
                          ? 'typing…'
                          : '${p.activeLabel(now)} · ${p.distanceLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.typing || p.online
                            ? HuntrColors.online
                            : HuntrColors.muted,
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: 'View profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProfileScreen(profileId: p.id))),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.isEmpty && !c.typing
                ? ChatIntro(profile: p)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: msgs.length + (c.typing ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (c.typing && i == 0) return const TypingBubble();
                      final idx = c.typing ? i - 1 : i;
                      final m = msgs[idx];
                      final older =
                          idx + 1 < msgs.length ? msgs[idx + 1] : null;
                      final newer = idx > 0 ? msgs[idx - 1] : null;
                      final showTime = older == null ||
                          m.sentAt.difference(older.sentAt).inMinutes.abs() >
                              30;
                      final groupedWithNewer =
                          newer != null && newer.fromMe == m.fromMe;
                      return Column(children: [
                        if (showTime) TimeDivider(time: m.sentAt, now: now),
                        switch (m.kind) {
                          MessageKind.notice => ChatNotice(text: m.text),
                          MessageKind.album => AlbumBubble(
                              message: m,
                              ownerName: m.fromMe ? 'Your' : '${p.name}\'s'),
                          MessageKind.text => MessageBubble(
                              message: m,
                              tail: !groupedWithNewer,
                              showStatus: m.fromMe && newer == null),
                        },
                      ]);
                    },
                  ),
          ),
          if (!connected)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  const Icon(Icons.lock_outline, color: HuntrColors.orange),
                  const SizedBox(height: 6),
                  Text(
                      'You can message ${p.name} once a chat request is accepted.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => ProfileScreen(profileId: p.id))),
                    child: const Text('View profile'),
                  ),
                ]),
              ),
            ),
          if (connected) ..._composer(p),
        ],
      ),
    );
  }

  /// A keyboard's Enter sends the message; Shift+Enter is left to the box
  /// (a new line), as is Enter while an input method is still composing.
  KeyEventResult _enterSends(KeyEvent event, Profile p) {
    // Esc while replying: stop replying (not close the chat)
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _replyingTo() != null) {
      if (event is KeyDownEvent) _cancelReply();
      return KeyEventResult.handled;
    }
    final enter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (_input.value.composing.isValid) return KeyEventResult.ignored;
    // swallow the key's repeat and release too, so no new line slips in
    if (event is KeyDownEvent) _send(p, _input.text);
    return KeyEventResult.handled;
  }

  /// Quick replies (while the box is empty) and the message box.
  /// The message box; [anonymous]: text and GIFs only (no attachments).
  List<Widget> _composer(Profile p, {bool anonymous = false}) {
    // room for a separate GIF button beside +
    final wideComposer = MediaQuery.sizeOf(context).width >= 600;
    return [
      if (_replyingTo() case final replying?)
        ReplyBanner(
          message: replying,
          otherName: p.name,
          onCancel: _cancelReply,
        )
      // ---- quick replies keep the first message low-effort ----
      else if (_input.text.isEmpty)
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: quickReplies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ActionChip(
              label: Text(quickReplies[i]),
              onPressed: () => _send(p, quickReplies[i]),
            ),
          ),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
          child: Row(children: [
            // no photos, videos, albums or locations in an anonymous chat
            if (_conversationId != null && !anonymous) ...[
              IconButton(
                key: const Key('attachButton'),
                tooltip: 'Photo, video or album trade',
                style: IconButton.styleFrom(
                  backgroundColor: HuntrColors.surfaceHigh,
                  minimumSize: const Size(44, 44),
                ),
                icon: const Icon(Icons.add_rounded, color: HuntrColors.orange),
                onPressed: () => showAttachMenu(context,
                    conversationId: _conversationId!,
                    recipient: p,
                    // on a phone GIFs are in this menu
                    onGif: wideComposer ? null : () => _pickGif(p)),
              ),
              const SizedBox(width: 6),
            ],
            // GIFs and stickers: their own button on wide screens, and in
            // anonymous chats (which have no + menu); on a phone in a
            // direct chat they're in the + menu
            if (_conversationId != null && (anonymous || wideComposer)) ...[
              IconButton(
                key: const Key('gifButton'),
                tooltip: 'GIF or sticker',
                style: IconButton.styleFrom(
                  backgroundColor: HuntrColors.surfaceHigh,
                  minimumSize: const Size(44, 44),
                ),
                icon: const Icon(Icons.gif_box_outlined,
                    color: HuntrColors.orange),
                onPressed: () => _pickGif(p),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              // Enter sends; Shift+Enter adds a new line
              child: Focus(
                onKeyEvent: (_, event) => _enterSends(event, p),
                child: TextField(
                  key: const Key('messageInput'),
                  controller: _input,
                  focusNode: _inputFocus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: 'Message ${p.name}…'),
                  onSubmitted: (v) => _send(p, v),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedScale(
              scale: _input.text.trim().isEmpty ? 0.85 : 1,
              duration: const Duration(milliseconds: 150),
              child: IconButton.filled(
                key: const Key('sendButton'),
                tooltip: 'Send',
                style: IconButton.styleFrom(
                  backgroundColor: HuntrColors.orange,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.send_rounded),
                onPressed: _input.text.trim().isEmpty
                    ? null
                    : () => _send(p, _input.text),
              ),
            ),
          ]),
        ),
      ),
    ];
  }

  /// Their profile, from the chat header: shown at once, then with all their
  /// photos once loaded. Its Message button comes back here.
  /// The block between us, if any: as last checked with the backend, else
  /// as the chat list says.
  BlockStatus? _blockWith(Profile p) {
    final id = p.backendId;
    if (id == null) {
      // someone anonymous (no id): as the chat list says
      return p.blockedByMe || p.blockedMe
          ? BlockStatus(blockedByMe: p.blockedByMe, blockedMe: p.blockedMe)
          : null;
    }
    return BlockScope.of(context)?.statusOf(id) ??
        (p.blockedByMe || p.blockedMe
            ? BlockStatus(blockedByMe: p.blockedByMe, blockedMe: p.blockedMe)
            : null);
  }

  /// Block them (after "Block this user?"): the chat stays, closed.
  Future<void> _block(Profile p) async {
    final blocks = BlockScope.read(context);
    final id = p.backendId;
    if (blocks == null || id == null || !await confirmBlock(context)) return;
    if (!mounted) return;
    try {
      await blocks.block(id);
      if (!mounted) return;
      AppScope.read(context).block(p.id);
      unawaited(_messaging?.refresh());
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Unmatch them (after confirming): the chat leaves both our lists, so
  /// this screen closes.
  /// Unmatching an anonymous chat (direct chats have no Unmatch).
  Future<void> _unmatch(Profile p, int conversationId) async {
    final messaging = _messaging;
    if (messaging == null || !await confirmUnmatch(context, p.name)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await messaging.unmatchAnonymous(conversationId);
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Unmatched. Changed your mind? Undo it anytime in Settings → Unmatched users.')));
      if (widget.onClose case final close?) {
        close();
      } else {
        navigator.pop();
      }
    } on BackendException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openProfile(Profile p) => openPersonProfile(context, p,
      // Message on their profile comes back to this chat
      onMessage: (page) => Navigator.of(page).pop());

  /// The anonymous side answers the request to see their profile.
  bool _answering = false;

  Future<void> _answerReveal(int conversationId, bool accept) async {
    final messaging = _messaging;
    if (messaging == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(accept ? 'Ready to reveal yourself? 🎭' : 'Stay a mystery?'),
        content: Text(accept
            ? 'They’ll finally see who you are, and you can keep chatting in '
                'Direct. Exciting! ✨'
            : 'This chat will end for both of you, and your identity stays '
                'private. That’s completely okay.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now')),
          FilledButton(
              key: const Key('confirmRevealAnswer'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(accept ? 'Show my profile' : 'Unmatch')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _answering = true);
    try {
      final answer = await messaging.answerReveal(conversationId, accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(answer?.accepted == true
              ? 'Mask off! 🎉 They can see your profile now.'
              : 'Done. Your secret’s safe 🤫')));
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      unawaited(messaging.refresh());
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  /// Why I can't write in this anonymous chat (null: I can).
  String? _closedReason(ConversationSummary summary) {
    if (summary.canSend) return null;
    if (summary.unmatched) {
      return 'This chat has ended.';
    }
    final reveal = summary.reveal?.status;
    if (summary.anonymous?.iAmAnonymous == true) {
      if (reveal == RevealStatus.pending) {
        return 'Pick an option above to keep the chat going 👆';
      }
      if (reveal != null) return 'This chat has ended.';
      if (!_app.anonymousMessaging) {
        return 'Anonymous messaging is off. Turn it back on in Settings to keep chatting.';
      }
    }
    return 'You can’t send messages in this chat right now.';
  }

  /// A backend conversation: history (older pages as you scroll up), my
  /// pending/failed messages, and live updates from [MessagingState].
  Widget _buildConversation(BuildContext context) {
    final messaging = MessagingScope.of(context)!;
    // live sharing stopped on its own (e.g. location access was turned off)
    if (messaging.liveProblem case final problem?) {
      messaging.liveProblem = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(problem)));
        }
      });
    }
    final id = _conversationId!;
    final summary = messaging.summary(id);
    final anonymous = summary?.anonymous;
    // someone anonymous to me: as the list now shows them (their real
    // profile once they've shown it)
    final p = widget.other!.isAnonymous && summary != null
        ? summary.other
        : widget.other!;
    final movedTo = messaging.movedToDirect(id);
    // unmatched (by either of us): the chat is gone
    final gone = messaging.isGone(id);
    final closed =
        anonymous != null && summary != null ? _closedReason(summary) : null;
    final now = DateTime.now();
    final history = messaging.messagesOf(id);
    final msgs = history.reversed.toList();
    final loaded = messaging.isLoaded(id);
    final older = messaging.hasOlder(id);
    final newestMine = msgs.where((m) => m.fromMe).firstOrNull;
    // a block between us: the history stays, nothing can be sent
    final block = _blockWith(p);
    final blocked = block?.blocked ?? false;
    final typing = !blocked && messaging.isTyping(id);
    // reactions and replies only while I can write here
    final interactive = !blocked && closed == null;

    Message asMessage(ChatMessage m) => Message(
          id: '${m.id ?? m.clientId}',
          fromMe: m.fromMe,
          text: m.body,
          sentAt: m.sentAt,
          status: m.failed
              ? MessageStatus.failed
              : m.pending
                  ? MessageStatus.sending
                  : m.read
                      ? MessageStatus.read
                      : MessageStatus.sent,
        );

    final onClose = widget.onClose;
    final page = Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: onClose == null
            ? null
            : IconButton(
                key: const Key('closeChat'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: onClose,
              ),
        actions: [
          // direct chats; an anonymous one has its buttons in the header
          if (!blocked && !gone && anonymous == null && p.backendId != null)
            PopupMenuButton<String>(
              key: const Key('chatMenu'),
              tooltip: 'More',
              onSelected: (_) => _block(p),
              itemBuilder: (_) => [
                if (BlockScope.of(context) != null)
                  const PopupMenuItem(
                      value: 'block',
                      child: ListTile(
                          leading: Icon(Icons.block), title: Text('Block'))),
              ],
            ),
        ],
        // over the centred messages on wide screens
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Row(children: [
              Expanded(
                // tap the person to see their profile
                child: InkWell(
                  key: const Key('chatHeader'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => blocked
                      ? Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BlockedScreen(status: block!)))
                      // someone anonymous: only their anonymous profile
                      : p.isAnonymous
                          ? Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  AnonymousProfileScreen(conversationId: id)))
                          : _openProfile(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      // no online dot while a block is between us
                      anonymous != null && anonymous.iAmAnonymous
                          ? MaskOverlay(
                              size: 40,
                              online: p.online && !blocked,
                              child: Avatar(
                                  profile: p, size: 40, showOnline: false))
                          : Avatar(profile: p, size: 40, showOnline: !blocked),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.nameAndAge,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              // where I'm anonymous: whom they see
                              if (anonymous != null && anonymous.iAmAnonymous)
                                Row(children: [
                                  const Icon(Icons.theater_comedy_outlined,
                                      size: 13, color: HuntrColors.orange),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                        'You’re ${anonymous.name} to them',
                                        key: const Key('anonymousAsHeader'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: HuntrColors.orange)),
                                  ),
                                ])
                              // no presence while a block is between us
                              else if (!blocked)
                                Text(typing ? 'typing…' : p.activeLabel(now),
                                    key: typing
                                        ? const Key('typingHeader')
                                        : null,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: typing
                                            ? HuntrColors.orange
                                            : p.online
                                                ? HuntrColors.online
                                                : HuntrColors.muted)),
                            ]),
                      ),
                    ]),
                  ),
                ),
              ),
              // an anonymous chat: the recipient's actions at the right
              // (no Block; the one who wrote first can't unmatch here)
              if (anonymous != null &&
                  !anonymous.iAmAnonymous &&
                  !blocked &&
                  !gone &&
                  summary?.unmatched != true) ...[
                if (summary?.reveal == null)
                  IconButton(
                    key: const Key('requestRevealButton'),
                    tooltip: 'Request to see profile',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: () => askToSeeProfile(context,
                        conversationId: id, name: anonymous.name),
                  ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  key: const Key('unmatchButton'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFFFF8A80),
                    side: const BorderSide(color: Color(0x66FF8A80)),
                  ),
                  onPressed: () => _unmatch(p, id),
                  icon: const Icon(Icons.person_remove_outlined, size: 18),
                  label: const Text('Unmatch'),
                ),
              ],
            ]),
          ),
        ),
      ),
      // wide screens: a centred column, not bubbles across the whole window
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            if (anonymous != null && summary?.reveal != null)
              RevealBanner(
                anonymous: anonymous,
                reveal: summary!.reveal!,
                busy: _answering,
                onAccept: () => _answerReveal(id, true),
                onDecline: () => _answerReveal(id, false),
              ),
            if (blocked || anonymous != null)
              const SizedBox.shrink()
            else if (messaging.liveSessionIn(id) case final live?)
              _LiveBanner(
                onOpen: () => _openLive(live, p),
                onStop: () => messaging.stopLiveLocation(live),
              )
            else if (msgs
                    .where((m) => m.liveLocation?.pending == true)
                    .firstOrNull
                case final asked?)
              _PendingLiveBanner(
                message: asked,
                name: p.name.isEmpty ? 'them' : p.name,
                onAccept: () =>
                    _liveAction(() => messaging.acceptLiveLocation(asked)),
                onDecline: () =>
                    _liveAction(() => messaging.declineLiveLocation(asked)),
                onCancel: () =>
                    _liveAction(() => messaging.cancelLiveLocation(asked)),
              ),
            Expanded(
              child: !loaded && messaging.loadErrorOf(id) != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LoadFailedCard(
                          title: "Couldn't load this chat",
                          message: messaging.loadErrorOf(id)!,
                          onRetry: () => messaging.load(id),
                          retryKey: const Key('chatRetry'),
                        ),
                      ),
                    )
                  : !loaded
                      ? const Center(child: CircularProgressIndicator())
                      : msgs.isEmpty && !typing
                          // centred, and scrolls when the keyboard leaves
                          // too little room
                          ? LayoutBuilder(
                              builder: (context, box) => SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(minHeight: box.maxHeight),
                                  child: Center(
                                    child: anonymous != null &&
                                            anonymous.iAmAnonymous
                                        ? AnonymousIntro(
                                            anonymous: anonymous, to: p.name)
                                        : ChatIntro(profile: p),
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              key: const Key('messageList'),
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              // the typing bubble sits below the newest message
                              itemCount: msgs.length +
                                  (older ? 1 : 0) +
                                  (typing ? 1 : 0),
                              itemBuilder: (_, index) {
                                if (typing && index == 0) {
                                  return const TypingBubble(
                                      key: Key('typingBubble'));
                                }
                                final i = typing ? index - 1 : index;
                                if (i == msgs.length) {
                                  // more history above: loads as it comes
                                  // into view (also when the messages don't
                                  // fill the screen, so there's no scrolling)
                                  return _OlderMessages(
                                    failed: messaging.olderFailed(id),
                                    onVisible: () => messaging.loadOlder(id),
                                    onRetry: () =>
                                        messaging.loadOlder(id, retry: true),
                                  );
                                }
                                final m = msgs[i];
                                final olderMsg =
                                    i + 1 < msgs.length ? msgs[i + 1] : null;
                                final newer = i > 0 ? msgs[i - 1] : null;
                                final showTime = olderMsg == null ||
                                    m.sentAt
                                            .difference(olderMsg.sentAt)
                                            .inMinutes
                                            .abs() >
                                        30;
                                final showStatus = m.fromMe &&
                                    (m.pending || identical(m, newestMine));
                                final Widget card = switch (m.type) {
                                  // a story reply is a text with "Replied to your story" over it
                                  ChatMessageType.text ||
                                  ChatMessageType.storyReply =>
                                    Reactable(
                                      message: m,
                                      enabled: interactive,
                                      onReact: (e) => _react(m, e),
                                      onReply: () => _startReply(m),
                                      otherName: p.name,
                                      onQuoteTap: _jumpTo,
                                      highlighted: _highlight == m.id,
                                      // under my newest message: Sent / Read
                                      below: showStatus
                                          ? MessageStatusLine(
                                              status: asMessage(m).status)
                                          : null,
                                      child: StoryReplyLabel.over(
                                        m,
                                        onOpenStory: () => _openStory(m, p),
                                        MessageBubble(
                                          key: Key(
                                              'message-${m.id ?? m.clientId}'),
                                          message: asMessage(m),
                                          tail: newer == null ||
                                              newer.fromMe != m.fromMe,
                                          showStatus: false,
                                        ),
                                        otherName: p.name,
                                      ),
                                    ),
                                  ChatMessageType.albumTrade
                                      when m.trade != null =>
                                    TradeCard(
                                      message: m,
                                      other: p,
                                      now: now,
                                      onOpenMine: _openMyAlbum,
                                      onOpenTheirs: () => Navigator.of(context)
                                          .push(MaterialPageRoute(
                                              builder: (_) =>
                                                  TradedAlbumViewerScreen(
                                                      message: m))),
                                      busy:
                                          _changingTrades.contains(m.trade!.id),
                                      onRespond: () => answerAlbumTrade(context,
                                          conversationId: id,
                                          sender: p,
                                          trade: m.trade!),
                                      onCancel: () => _cancelTrade(m),
                                      onJumpTo: _jumpTo,
                                      wrapOffer: (offer) =>
                                          _actions(m, p, offer),
                                    ),
                                  ChatMessageType.albumTrade =>
                                    const SizedBox.shrink(),
                                  // the album chosen in return, at the
                                  // bottom when it was chosen
                                  ChatMessageType.albumTradeReturn
                                      when m.trade != null =>
                                    TradeCard(
                                      message: m,
                                      other: p,
                                      now: now,
                                      returnOnly: true,
                                      onOpenMine: _openMyAlbum,
                                      onOpenTheirs: () => Navigator.of(context)
                                          .push(MaterialPageRoute(
                                              builder: (_) =>
                                                  TradedAlbumViewerScreen(
                                                      message: m))),
                                      onRespond: () {},
                                      onCancel: () {},
                                      wrapOffer: (card) => _actions(m, p, card),
                                    ),
                                  ChatMessageType.albumTradeReturn =>
                                    const SizedBox.shrink(),
                                  ChatMessageType.location
                                      when m.location != null =>
                                    _actions(
                                        m,
                                        p,
                                        LocationBubble(
                                          message: m,
                                          position: messaging.positionOf(m),
                                          now: now,
                                          // whose it is: their photo is the pin
                                          person: m.fromMe
                                              ? _app.myPublicProfile
                                              : p,
                                          onOpen: () => Navigator.of(context)
                                              .push(MaterialPageRoute(
                                                  builder: (_) => LocationMapScreen(
                                                      message: m,
                                                      person: m.fromMe
                                                          ? _app.myPublicProfile
                                                          : p,
                                                      name: m.fromMe
                                                          ? 'You'
                                                          : p.name))),
                                          onStop: () =>
                                              messaging.stopSharingLocation(m),
                                        )),
                                  ChatMessageType.location =>
                                    const SizedBox.shrink(),
                                  ChatMessageType.liveLocation
                                      when m.liveLocation != null =>
                                    _actions(
                                        m,
                                        p,
                                        LiveLocationCard(
                                          message: m,
                                          me: _app.myPublicProfile,
                                          other: p,
                                          positions:
                                              messaging.livePositionsOf(m.id!),
                                          onAccept: () => _liveAction(() =>
                                              messaging.acceptLiveLocation(m)),
                                          onDecline: () => _liveAction(() =>
                                              messaging.declineLiveLocation(m)),
                                          onCancel: () => _liveAction(() =>
                                              messaging.cancelLiveLocation(m)),
                                          onStop: () => _liveAction(() =>
                                              messaging.stopLiveLocation(m)),
                                          onOpen: () => _openLive(m, p),
                                        )),
                                  ChatMessageType.liveLocation =>
                                    const SizedBox.shrink(),
                                  ChatMessageType.revealRequest =>
                                    RevealRequestCard(fromMe: m.fromMe),
                                  ChatMessageType.tap => TapCard(
                                      answers: m.tapAnswers,
                                      fromMe: m.fromMe,
                                      otherName: p.name),
                                  ChatMessageType.reveal => RevealedCard(
                                      name: m.body,
                                      avatar: m.revealedAvatar,
                                      fromMe: m.fromMe,
                                      person: p,
                                      onViewProfile: p.isAnonymous
                                          ? null
                                          : () => _openProfile(p),
                                    ),
                                  ChatMessageType.gif when m.gif == null =>
                                    const SizedBox.shrink(),
                                  // photos, videos and GIFs
                                  _ => Reactable(
                                      message: m,
                                      enabled: !blocked,
                                      onReact: (e) => _react(m, e),
                                      onReply: () => _startReply(m),
                                      otherName: p.name,
                                      onQuoteTap: _jumpTo,
                                      highlighted: _highlight == m.id,
                                      below: showStatus
                                          ? MessageStatusLine(
                                              status: asMessage(m).status,
                                              detail: m.failed ? m.error : null)
                                          : null,
                                      child: m.type == ChatMessageType.gif
                                          ? GifBubble(message: m)
                                          : MediaBubble(
                                              message: m,
                                              now: now,
                                              onOpen: () => Navigator.of(
                                                      context)
                                                  .push(MaterialPageRoute(
                                                      builder: (_) =>
                                                          ChatMediaViewerScreen(
                                                              message: m))),
                                              onPreviewFailed: () =>
                                                  _refreshPreview(m),
                                            ),
                                    ),
                                };
                                // cards are messages too: Sent / Read under my newest
                                final Widget bubble = showStatus &&
                                        (m.type == ChatMessageType.albumTrade ||
                                            m.type ==
                                                ChatMessageType
                                                    .albumTradeReturn ||
                                            m.type ==
                                                ChatMessageType.location ||
                                            m.type ==
                                                ChatMessageType.liveLocation)
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                            card,
                                            MessageStatusLine(
                                                status: asMessage(m).status),
                                          ])
                                    : card;
                                return Column(key: _keyFor(m), children: [
                                  if (showTime)
                                    TimeDivider(time: m.sentAt, now: now),
                                  m.failed
                                      ? GestureDetector(
                                          key: Key('retry-${m.clientId}'),
                                          onTap: () => messaging.retry(
                                              id, p, m.clientId!),
                                          child: bubble)
                                      : bubble,
                                ]);
                              },
                            ),
            ),
            if (movedTo != null && movedTo != id)
              MovedToDirectBar(
                  onOpen: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => ChatScreen.conversation(
                              conversationId: movedTo,
                              other: messaging.summary(movedTo)?.other ?? p))))
            else if (blocked)
              _BlockedBar(status: block!)
            else if (gone)
              const AnonymousClosedBar(message: 'This chat has ended.')
            else if (closed != null)
              AnonymousClosedBar(message: closed)
            else
              ..._composer(p, anonymous: anonymous != null),
          ]),
        ),
      ),
    );
    if (onClose == null) return page;
    // Esc closes the chat beside the list, as Back would a page
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Focus(autofocus: true, child: page),
    );
  }
}

/// Where the message box was, while a block is between us. To the person
/// blocked: "You are blocked by this person".
class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.status});

  final BlockStatus status;

  @override
  Widget build(BuildContext context) {
    final byMe = status.blockedByMe && !status.blockedMe;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('blockedComposer'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.block_rounded, color: HuntrColors.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(byMe ? blockedByMeMessage : blockedByThemMessage,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

/// The row above the oldest message while there are older ones: a spinner
/// that loads them once it's built (shown), or "Tap to retry" after a
/// failure.
class _OlderMessages extends StatelessWidget {
  const _OlderMessages(
      {required this.failed, required this.onVisible, required this.onRetry});

  final bool failed;
  final VoidCallback onVisible;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: TextButton.icon(
          key: const Key('olderRetry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Couldn’t load older messages · Retry'),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    return const Padding(
      key: Key('olderLoading'),
      padding: EdgeInsets.all(12),
      child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

/// A live location request waiting here: mine ("You're requesting…",
/// Cancel request), or theirs (Decline / Accept).
class _PendingLiveBanner extends StatelessWidget {
  const _PendingLiveBanner(
      {required this.message,
      required this.name,
      required this.onAccept,
      required this.onDecline,
      required this.onCancel});

  final ChatMessage message;
  final String name;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final info = message.liveLocation!;
    final compact = TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10));
    return Container(
      key: const Key('pendingLiveBanner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: HuntrColors.orange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.share_location_rounded,
            color: HuntrColors.orange, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            info.canAccept
                ? '$name wants to share live locations'
                : 'You’re requesting to share live locations with $name',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (info.canAccept) ...[
          TextButton(
            key: const Key('declineLiveBanner'),
            style: compact.copyWith(
                foregroundColor:
                    const WidgetStatePropertyAll(HuntrColors.muted)),
            onPressed: onDecline,
            child: const Text('Decline'),
          ),
          FilledButton(
            key: const Key('acceptLiveBanner'),
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: HuntrColors.orange,
                foregroundColor: Colors.black,
                shape: const StadiumBorder()),
            onPressed: onAccept,
            child: const Text('Accept'),
          ),
        ] else if (info.canCancel)
          TextButton(
            key: const Key('cancelLiveBanner'),
            style: compact.copyWith(
                foregroundColor:
                    const WidgetStatePropertyAll(HuntrColors.coral)),
            onPressed: onCancel,
            child: const Text('Cancel request'),
          ),
      ]),
    );
  }
}

/// While a live session runs here: "You're sharing a live connection",
/// tap for the map, Stop ends it for both.
class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.onOpen, required this.onStop});

  final VoidCallback onOpen;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('liveBanner'),
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: HuntrColors.orange.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: HuntrColors.orange.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            const Icon(Icons.share_location_rounded,
                color: HuntrColors.orange, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('You’re sharing a live connection',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              key: const Key('stopLiveBanner'),
              style: TextButton.styleFrom(foregroundColor: HuntrColors.coral),
              onPressed: onStop,
              child: const Text('Stop'),
            ),
          ]),
        ),
      ),
    );
  }
}
