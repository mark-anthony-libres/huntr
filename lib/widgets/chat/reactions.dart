import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';
import 'reply.dart';

/// The quick reactions, in the bar above a message.
const quickReactions = ['❤️', '😆', '😮', '😢', '😡', '👍'];

/// A message in the chat, with what can be done to it: reply (the arrow on
/// hover, or swipe it right), and react to their text, photos and videos
/// (long-press, right-click, or the smiley on hover; the emoji bar opens
/// above it). Its reactions show in a small pill under it, and a reply
/// shows the message it answers above it.
class Reactable extends StatefulWidget {
  const Reactable(
      {super.key,
      required this.message,
      required this.onReact,
      required this.child,
      this.below,
      this.onReply,
      this.otherName = '',
      this.onQuoteTap,
      this.highlighted = false,
      this.enabled = true});

  final ChatMessage message;

  /// An emoji was picked (the same as mine again: remove mine).
  final ValueChanged<String> onReact;

  /// The bubble.
  final Widget child;

  /// Under the reactions (e.g. Sent / Read).
  final Widget? below;

  /// Start replying to this message (null: it can't be replied to yet).
  final VoidCallback? onReply;

  /// The other person's name, for the quote.
  final String otherName;

  /// The quote was tapped: go to the message it shows (by id).
  final ValueChanged<int>? onQuoteTap;

  /// Just jumped to (from a reply's quote): briefly marked.
  final bool highlighted;

  /// Off while a block is between us: no reply, no reactions (its own
  /// reactions still show).
  final bool enabled;

  @override
  State<Reactable> createState() => _ReactableState();
}

class _ReactableState extends State<Reactable> {
  final _bubble = GlobalKey();
  bool _hover = false;

  /// How far it's been swiped right (to reply).
  double _swipe = 0;
  static const _swipeToReply = 56.0;

  Future<void> _pick() async {
    final box = _bubble.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final emoji = await showReactionBar(context,
        anchor: rect,
        mine: widget.message.myReaction,
        alignRight: widget.message.fromMe);
    if (emoji != null && mounted) widget.onReact(emoji);
  }

  void _swiped(DragEndDetails _) {
    if (_swipe >= _swipeToReply) widget.onReply?.call();
    setState(() => _swipe = 0);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final me = m.fromMe;
    // my own messages only show the other person's reactions
    final can = widget.enabled && m.canReact;
    final reply = m.id == null || !widget.enabled ? null : widget.onReply;
    Widget hoverButton(
            {required Key key,
            required String tooltip,
            required IconData icon,
            required VoidCallback onPressed}) =>
        AnimatedOpacity(
          opacity: _hover ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: IgnorePointer(
            ignoring: !_hover,
            child: IconButton(
              key: key,
              tooltip: tooltip,
              visualDensity: VisualDensity.compact,
              icon: Icon(icon, size: 20, color: HuntrColors.muted),
              onPressed: onPressed,
            ),
          ),
        );
    final buttons = [
      if (can)
        hoverButton(
            key: Key('reactButton-${m.id}'),
            tooltip: 'React',
            icon: Icons.add_reaction_outlined,
            onPressed: _pick),
      if (reply != null)
        hoverButton(
            key: Key('replyButton-${m.id}'),
            tooltip: 'Reply',
            icon: Icons.reply_rounded,
            onPressed: reply),
    ];
    final bubble = GestureDetector(
      key: Key('reactable-${m.id}'),
      onLongPress: can ? _pick : null,
      onSecondaryTap: can ? _pick : null,
      onHorizontalDragUpdate: reply == null
          ? null
          : (d) => setState(() =>
              _swipe = (_swipe + d.delta.dx).clamp(0.0, _swipeToReply + 16)),
      onHorizontalDragEnd: reply == null ? null : _swiped,
      onHorizontalDragCancel:
          reply == null ? null : () => setState(() => _swipe = 0),
      child: KeyedSubtree(key: _bubble, child: widget.child),
    );
    final quote = m.replyTo;
    final content = Column(
      crossAxisAlignment:
          me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (quote != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ReplyQuote(
                  quote: quote,
                  otherName: widget.otherName,
                  mine: me,
                  onTap: widget.onQuoteTap == null
                      ? null
                      : () => widget.onQuoteTap!(quote.id)),
            ),
          ),
        Row(
          mainAxisAlignment:
              me ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (me) ...buttons.reversed,
            Flexible(child: bubble),
            if (!me) ...buttons,
          ],
        ),
        if (m.reactions.isNotEmpty)
          // tucked under the bubble's corner
          Transform.translate(
            offset: const Offset(0, -10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ReactionPill(
                  reactions: m.reactions, onTap: can ? _pick : null),
            ),
          ),
        if (widget.below != null) widget.below!,
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: widget.highlighted
              ? HuntrColors.orange.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(children: [
          // swiping: the reply arrow shows on the left as it's pulled
          if (_swipe > 0)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: (_swipe / _swipeToReply).clamp(0.0, 1.0),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: _swipe >= _swipeToReply
                        ? HuntrColors.orange
                        : HuntrColors.surfaceHigh,
                    child: Icon(Icons.reply_rounded,
                        size: 18,
                        color: _swipe >= _swipeToReply
                            ? Colors.black
                            : Colors.white),
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_swipe, 0), child: content),
        ]),
      ),
    );
  }
}

/// The reactions on a message: each emoji once (with how many, when we both
/// picked it).
class ReactionPill extends StatelessWidget {
  const ReactionPill({super.key, required this.reactions, this.onTap});

  final List<MessageReaction> reactions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    return GestureDetector(
      key: const Key('reactionPill'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuntrColors.night, width: 2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final MapEntry(key: emoji, value: n) in counts.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(n > 1 ? '$emoji $n' : emoji,
                  style: const TextStyle(fontSize: 15, color: Colors.white)),
            ),
        ]),
      ),
    );
  }
}

/// The emoji bar above (or below, near the top) [anchor]: the quick
/// reactions, mine highlighted, and + for any emoji. The emoji picked, or
/// null.
Future<String?> showReactionBar(BuildContext context,
    {required Rect anchor, String? mine, bool alignRight = false}) async {
  final picked = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close reactions',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, __) =>
        _ReactionBar(anchor: anchor, mine: mine, alignRight: alignRight),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(animation), child: child),
    ),
  );
  if (picked != '+' || !context.mounted) return picked;
  return showEmojiPicker(context);
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar(
      {required this.anchor, required this.mine, required this.alignRight});

  final Rect anchor;
  final String? mine;
  final bool alignRight;

  static const _height = 56.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    // above the message, or below it when there's no room
    final y = anchor.top - _height - 8 > top + 8
        ? anchor.top - _height - 8
        : anchor.bottom + 8;
    final bar = Material(
      key: const Key('reactionBar'),
      color: HuntrColors.surfaceHigh,
      elevation: 6,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final emoji in quickReactions)
            _EmojiButton(
                emoji: emoji,
                selected: emoji == mine,
                onTap: () => Navigator.of(context).pop(emoji)),
          if (mine != null && !quickReactions.contains(mine))
            _EmojiButton(
                emoji: mine!,
                selected: true,
                onTap: () => Navigator.of(context).pop(mine)),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: IconButton.filledTonal(
              key: const Key('moreReactions'),
              tooltip: 'More',
              style: IconButton.styleFrom(
                  backgroundColor: HuntrColors.border,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.add_rounded),
              onPressed: () => Navigator.of(context).pop('+'),
            ),
          ),
        ]),
      ),
    );
    // lined up with the message's own edge (not the screen's: beside a
    // chat list the message is far from it)
    final edge = alignRight ? size.width - anchor.right : anchor.left;
    return Stack(children: [
      Positioned(
        top: y.clamp(top + 8, size.height - _height - 8),
        left: alignRight ? null : edge.clamp(12.0, size.width / 2),
        right: alignRight ? edge.clamp(12.0, size.width / 2) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: size.width - edge.clamp(12.0, size.width / 2) - 12),
          child: FittedBox(fit: BoxFit.scaleDown, child: bar),
        ),
      ),
    ]);
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton(
      {required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      key: Key('react-$emoji'),
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: selected
            ? const BoxDecoration(
                shape: BoxShape.circle, color: HuntrColors.border)
            : null,
        child: Text(emoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

/// Any emoji, from a sheet of them by kind.
Future<String?> showEmojiPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: ListView(
            key: const Key('emojiPicker'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final (title, emojis) in _allEmojis) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(title,
                      style: const TextStyle(
                          color: HuntrColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                Wrap(children: [
                  for (final emoji in emojis.split(' '))
                    InkResponse(
                      key: Key('pick-$emoji'),
                      onTap: () => Navigator.of(context).pop(emoji),
                      radius: 24,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 26))),
                      ),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );

const _allEmojis = [
  (
    'SMILEYS',
    '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😙 😋 😛 😜 '
        '🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 😌 😔 😪 😴 😷 🤒 '
        '🤕 🤢 🤮 🥵 🥶 🥴 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 😳 🥺 😦 '
        '😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 🤡 '
        '👻 👽 🤖 💩'
  ),
  (
    'GESTURES',
    '👍 👎 👌 🤌 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👋 🤚 🖐️ ✋ 👏 🙌 👐 🤲 '
        '🙏 🤝 💪 👀 👅 👄 💋'
  ),
  (
    'HEARTS',
    '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ❤️‍🔥 💯 💢 💥 '
        '💫 💦 🔥 ✨ ⭐ 🌟'
  ),
  (
    'FUN',
    '🎉 🎊 🎁 🏆 🥇 🍑 🍆 🍒 🍓 🍕 🍔 🍟 🍦 🍩 🍪 🎂 🍿 ☕ 🍺 🍻 🥂 🍷 '
        '🍸 🌈 🌹 🌸 🌻 🐶 🐱 🐻 🐼 🦄 🐍 🙈 🙉 🙊'
  ),
];
