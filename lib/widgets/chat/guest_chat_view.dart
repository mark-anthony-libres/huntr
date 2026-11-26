import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart' show Message, MessageStatus;
import '../../services/guest_chat_api.dart';
import '../../state/guest_chats_state.dart';
import '../../theme.dart';
import '../anonymous_avatar.dart';
import 'anonymous_chat.dart' show AnonymousClosedBar;
import 'gif_bubble.dart';
import 'gif_picker.dart';
import 'message_bubble.dart';
import 'reactions.dart';
import 'reply.dart';
import 'time_divider.dart';

/// A guest chat, the same for the host (in the app) and the guest (in a
/// browser): the anonymous chat's header (their animal and anonymous name,
/// whom they see me as, the time left), an [intro] at the start, the
/// messages as chat bubbles (with what chats do with one: react, reply,
/// copy), and the anonymous chat's message box (GIFs and stickers, and
/// text). When it ends, [ended] in place of the box.
class GuestChatView extends StatefulWidget {
  const GuestChatView({
    super.key,
    required this.controller,
    required this.intro,
    this.guestTag = false,
    this.actions = const [],
    this.ended,
    this.onOpenProfile,
    this.leading,
  });

  final GuestChatController controller;

  /// At the start of the chat (the anonymous chat's intro).
  final Widget intro;

  /// The host's side: a GUEST tag by their name.
  final bool guestTag;
  final List<Widget> actions;

  /// What shows once it ended (null: "This chat has ended").
  final Widget? ended;

  /// Their name tapped: their anonymous profile.
  final VoidCallback? onOpenProfile;
  final Widget? leading;

  @override
  State<GuestChatView> createState() => _GuestChatViewState();
}

class _GuestChatViewState extends State<GuestChatView> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  Timer? _clock;

  /// The message I'm answering (its quote over the box).
  GuestChatMessage? _replying;

  void _reply(GuestChatMessage m) {
    setState(() => _replying = m);
    _inputFocus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    // the minutes left count down
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final replying = _replying;
    setState(() => _replying = null);
    unawaited(widget.controller.sendText(text, replyTo: replying));
  }

  Future<void> _pickGif() async {
    final picked = await showGifPicker(context, source: widget.controller.gifs);
    if (picked is PickedGif) {
      final replying = _replying;
      setState(() => _replying = null);
      unawaited(widget.controller.sendGif(picked.gif, replyTo: replying));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final chat = c.chat;
        final now = DateTime.now();
        return Scaffold(
          appBar: AppBar(
            leading: widget.leading,
            titleSpacing: widget.leading == null ? 16 : 0,
            title: chat == null
                ? const SizedBox.shrink()
                : _Header(
                    chat: chat,
                    now: now,
                    ended: c.ended,
                    guestTag: widget.guestTag,
                    onTap: widget.onOpenProfile),
            actions: widget.actions,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(children: [
                Expanded(
                  child: c.loading && chat == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          key: const Key('guestMessages'),
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          children: [
                            for (final item in _items(c.messages, now).reversed)
                              item,
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: widget.intro,
                            ),
                          ],
                        ),
                ),
                if (c.ended)
                  widget.ended ??
                      const AnonymousClosedBar(message: 'This chat has ended.')
                else ...[
                  if (_replying != null)
                    ReplyBanner(
                      message: _replying!.toChatMessage(),
                      otherName: chat?.name ?? '',
                      onCancel: () => setState(() => _replying = null),
                    ),
                  _MessageBox(
                    input: _input,
                    focus: _inputFocus,
                    // nothing said yet: the box glows, to start there
                    glow: c.messages.isEmpty,
                    hint: chat == null ? 'Message' : 'Message ${chat.name}…',
                    onSend: _send,
                    onGif: c.gifs == null ? null : _pickGif,
                  ),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  /// The messages, with a time line when a gap opens (as in chats).
  List<Widget> _items(List<GuestChatMessage> messages, DateTime now) {
    final items = <Widget>[];
    DateTime? last;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (last == null || m.sentAt.difference(last).inMinutes >= 15) {
        items.add(TimeDivider(time: m.sentAt, now: now));
      }
      last = m.sentAt;
      final next = i + 1 < messages.length ? messages[i + 1] : null;
      final tail = next == null || next.mine != m.mine;
      items.add(_bubble(m, tail, isLast: next == null));
    }
    return items;
  }

  Widget _bubble(GuestChatMessage m, bool tail, {required bool isLast}) {
    final c = widget.controller;
    final seen = m.mine && m.id != null && (c.chat?.theyReadUpTo ?? 0) >= m.id!;
    final status = m.failed
        ? MessageStatus.failed
        : m.id == null
            ? MessageStatus.sending
            : seen
                ? MessageStatus.read
                : MessageStatus.sent;
    final chatMessage = m.toChatMessage();
    final Widget bubble = m.gif != null
        ? GifBubble(message: chatMessage)
        : MessageBubble(
            message: Message(
                id: m.clientId,
                fromMe: m.mine,
                text: m.text,
                sentAt: m.sentAt,
                status: status),
            tail: tail,
            // the status under my newest one (and any that failed)
            showStatus: m.mine && (isLast || m.failed));
    if (m.failed) {
      return GestureDetector(
        onTap: () => unawaited(c.retry(m)),
        child: bubble,
      );
    }
    // as in chats: react (long-press, double tap), reply (swipe), copy;
    // an ended chat is only to read (copy still works)
    return Reactable(
      key: ValueKey('guestMessage-${m.clientId}'),
      message: chatMessage,
      enabled: !c.ended && c.react != null,
      otherName: c.chat?.name ?? '',
      onReact: (emoji) => unawaited(c.reactTo(m, emoji)),
      onReply: c.ended ? null : () => _reply(m),
      child: bubble,
    );
  }
}

/// The anonymous chat's header: their animal and anonymous name, the time
/// left, and whom they see me as.
class _Header extends StatelessWidget {
  const _Header({
    required this.chat,
    required this.now,
    required this.ended,
    required this.guestTag,
    this.onTap,
  });

  final GuestChatSummary chat;
  final DateTime now;
  final bool ended;
  final bool guestTag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(children: [
      SizedBox.square(
        dimension: 40,
        child: AnonymousArt(animal: chat.avatar, radius: 20, size: 40),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Flexible(
                child: Text(chat.name,
                    key: const Key('guestChatName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (guestTag) ...[
                const SizedBox(width: 6),
                const GuestTag(),
              ],
              if (!ended && chat.started) ...[
                const SizedBox(width: 6),
                TimeLeftChip(minutes: chat.minutesLeft(now)),
              ],
            ]),
            if (chat.started) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.theater_comedy_outlined,
                    size: 13, color: HuntrColors.orange),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('You’re ${chat.myName} to them',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: HuntrColors.orange)),
                ),
              ]),
            ],
          ],
        ),
      ),
    ]);
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child:
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
    );
  }
}

/// "GUEST": a guest chat's guest (not on HUNTR).
class GuestTag extends StatelessWidget {
  const GuestTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: HuntrColors.orange.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('GUEST',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: HuntrColors.orange)),
      );
}

/// "8m left": how long a guest chat has (the guest's next message resets it).
class TimeLeftChip extends StatelessWidget {
  const TimeLeftChip({super.key, required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('guestTimeLeft'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('${minutes}m left',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: minutes <= 2 ? HuntrColors.orange : HuntrColors.muted)),
      );
}

/// The start of a guest chat, as the anonymous chat's intro: an animal, a
/// line, what to know, and [actions] (e.g. Join HUNTR).
class GuestChatIntro extends StatelessWidget {
  const GuestChatIntro({
    super.key,
    required this.animal,
    required this.title,
    required this.text,
    this.actions = const [],
  });

  final String animal;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox.square(
                dimension: 88,
                child: AnonymousArt(animal: animal, radius: 44, size: 88),
              ),
              const SizedBox(height: 14),
              Text(title,
                  key: const Key('guestChatIntro'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: HuntrColors.muted, height: 1.45)),
              for (final action in actions) ...[
                const SizedBox(height: 12),
                action,
              ],
            ]),
          ),
        ),
      );
}

/// The anonymous chat's message box: GIFs and stickers, and text (Send once
/// there's something to send).
class _MessageBox extends StatelessWidget {
  const _MessageBox(
      {required this.input,
      required this.focus,
      this.glow = false,
      required this.hint,
      required this.onSend,
      this.onGif});

  final TextEditingController input;
  final FocusNode focus;

  /// An orange glow around the box (before the first message).
  final bool glow;
  final String hint;
  final VoidCallback onSend;
  final VoidCallback? onGif;

  @override
  Widget build(BuildContext context) {
    final typing = input.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        child: Row(children: [
          if (onGif != null) ...[
            IconButton(
              key: const Key('guestGifButton'),
              tooltip: 'GIF or sticker',
              style: IconButton.styleFrom(
                backgroundColor: HuntrColors.surfaceHigh,
                minimumSize: const Size(44, 44),
              ),
              icon: Icon(Icons.gif_box_outlined, color: HuntrColors.orange),
              onPressed: onGif,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: _Glow(
              on: glow,
              child: TextField(
                key: const Key('guestMessageInput'),
                controller: input,
                focusNode: focus,
                minLines: 1,
                maxLines: 5,
                maxLength: 1000,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(hintText: hint),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: typing
                ? Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: IconButton.filled(
                      key: const Key('guestSendButton'),
                      tooltip: 'Send',
                      style: IconButton.styleFrom(
                        backgroundColor: HuntrColors.orange,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.send_rounded),
                      onPressed: onSend,
                    ),
                  )
                : const SizedBox(height: 48),
          ),
        ]),
      ),
    );
  }
}

/// A soft orange glow that breathes around [child] while [on] (still with
/// reduced motion).
class _Glow extends StatefulWidget {
  const _Glow({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(_Glow old) {
    super.didUpdateWidget(old);
    _run();
  }

  void _run() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.on && !still) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = widget.on ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse,
        child: widget.child,
        builder: (context, child) {
          final t = widget.on ? Curves.easeInOut.transform(_pulse.value) : 0.0;
          // (drawn as it is each frame: the pulse is the animation)
          return Container(
            key: const Key('guestMessageGlow'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: widget.on
                      ? HuntrColors.orange.withValues(alpha: 0.35 + 0.65 * t)
                      : Colors.transparent,
                  width: 1.5),
              boxShadow: widget.on
                  ? [
                      BoxShadow(
                          color: HuntrColors.orange
                              .withValues(alpha: 0.15 + 0.6 * t),
                          blurRadius: 6 + 26 * t,
                          spreadRadius: 6 * t),
                    ]
                  : const [],
            ),
            child: child,
          );
        },
      );
}
