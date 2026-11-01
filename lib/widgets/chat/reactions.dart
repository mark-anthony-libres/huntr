import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'reply.dart';

/// The quick reactions, in the bar above a message.
/// The reactions on this device's emoji bar, in their order (changed by
/// dragging them there; the defaults without app state).
List<String> quickReactionsOf(BuildContext context) =>
    AppScope.maybeRead(context)?.quickReactions ??
    AppState.defaultQuickReactions;

/// What a double tap gives: the bar's first reaction (❤️ when it's empty).
String firstReactionOf(BuildContext context) =>
    quickReactionsOf(context).firstOrNull ?? '❤️';

/// A message in the chat, with what can be done to it: reply (the arrow on
/// hover, or swipe it right), and react to their text, photos and videos
/// (long-press, right-click, or the smiley on hover; the emoji bar opens
/// above it). A double tap on their text, stickers and GIFs gives it the
/// first quick reaction (❤️) at once, with a heart that pops over it; it
/// only ever adds it (never takes it back). Photos and videos open on a tap,
/// so they don't wait to see if a second one comes (long-press reacts). Its reactions show in a small pill under it, and a reply
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

  /// The heart over the bubble after a double tap (its key replays it).
  int _hearts = 0;

  void _doubleTapped() {
    final first = firstReactionOf(context);
    if (widget.message.myReaction != first) widget.onReact(first);
    setState(() => _hearts++);
  }

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
      onDoubleTap: can &&
              m.type != ChatMessageType.image &&
              m.type != ChatMessageType.video
          ? _doubleTapped
          : null,
      onSecondaryTap: can ? _pick : null,
      onHorizontalDragUpdate: reply == null
          ? null
          : (d) => setState(() =>
              _swipe = (_swipe + d.delta.dx).clamp(0.0, _swipeToReply + 16)),
      onHorizontalDragEnd: reply == null ? null : _swiped,
      onHorizontalDragCancel:
          reply == null ? null : () => setState(() => _swipe = 0),
      child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            KeyedSubtree(key: _bubble, child: widget.child),
            // floats over the bubble (it takes no room, so nothing moves)
            if (_hearts > 0)
              Positioned.fill(
                child: Center(
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: _HeartPop(key: ValueKey(_hearts)),
                  ),
                ),
              ),
          ]),
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
  final any = await showEmojiPicker(context);
  // picked with +: it joins the bar (while there's room)
  if (any != null && context.mounted) {
    AppScope.maybeRead(context)?.addQuickReaction(any);
  }
  return any;
}

class _ReactionBar extends StatefulWidget {
  const _ReactionBar(
      {required this.anchor, required this.mine, required this.alignRight});

  final Rect anchor;
  final String? mine;
  final bool alignRight;

  static const _height = 56.0;

  @override
  State<_ReactionBar> createState() => _ReactionBarState();
}

/// The bar can be rearranged: press and drag a reaction to another place,
/// or onto the bin that shows at the bottom to take it off. A tap still
/// reacts. The new order is kept (on this device) when the drag ends.
class _ReactionBarState extends State<_ReactionBar> {
  late final List<String> _order = [...quickReactionsOf(context)];

  /// The reaction being dragged (null: none).
  String? _dragging;
  bool _overBin = false;

  void _moveBefore(String emoji, String target) {
    if (emoji == target) return;
    setState(() {
      final to = _order.indexOf(target);
      _order
        ..remove(emoji)
        ..insert(to, emoji);
    });
  }

  void _save() => AppScope.maybeRead(context)?.quickReactions = _order;

  Widget _draggable(String emoji) {
    final button = _EmojiButton(
        emoji: emoji,
        selected: emoji == widget.mine,
        onTap: () => Navigator.of(context).pop(emoji));
    return DragTarget<String>(
      // keyed by its emoji: moving it keeps the drag going (and its end)
      key: ValueKey(emoji),
      // hovering another reaction moves the dragged one there
      onWillAcceptWithDetails: (details) {
        _moveBefore(details.data, emoji);
        return true;
      },
      builder: (context, _, __) => LongPressDraggable<String>(
        key: Key('dragReaction-$emoji'),
        data: emoji,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          color: Colors.transparent,
          child: Text(emoji, style: const TextStyle(fontSize: 40)),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: button),
        onDragStarted: () => setState(() => _dragging = emoji),
        onDragEnd: (_) {
          setState(() {
            _dragging = null;
            _overBin = false;
          });
          _save();
        },
        child: button,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final top = padding.top;
    final anchor = widget.anchor;
    final mine = widget.mine;
    // above the message, or below it when there's no room
    final y = anchor.top - _ReactionBar._height - 8 > top + 8
        ? anchor.top - _ReactionBar._height - 8
        : anchor.bottom + 8;
    final bar = Material(
      key: const Key('reactionBar'),
      color: HuntrColors.surfaceHigh,
      elevation: 6,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final emoji in _order) _draggable(emoji),
          if (mine != null && !_order.contains(mine))
            _EmojiButton(
                emoji: mine,
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
    final edge = widget.alignRight ? size.width - anchor.right : anchor.left;
    return Stack(children: [
      Positioned(
        top: y.clamp(top + 8, size.height - _ReactionBar._height - 8),
        left: widget.alignRight ? null : edge.clamp(12.0, size.width / 2),
        right: widget.alignRight ? edge.clamp(12.0, size.width / 2) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: size.width - edge.clamp(12.0, size.width / 2) - 12),
          child: FittedBox(fit: BoxFit.scaleDown, child: bar),
        ),
      ),
      // while one is dragged: the bin, to take it off the bar
      if (_dragging != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: padding.bottom + 32,
          child: Center(
            child: DragTarget<String>(
              key: const Key('reactionBin'),
              onWillAcceptWithDetails: (_) {
                setState(() => _overBin = true);
                return true;
              },
              onLeave: (_) => setState(() => _overBin = false),
              onAcceptWithDetails: (details) =>
                  setState(() => _order.remove(details.data)),
              // a round bin, its lid opening as one is held over it
              builder: (context, _, __) => AnimatedScale(
                scale: _overBin ? 1.18 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _overBin ? HuntrColors.coral : HuntrColors.surfaceHigh,
                    border: Border.all(color: HuntrColors.coral, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 12),
                    ],
                  ),
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _overBin ? 1 : 0),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      builder: (context, open, _) => CustomPaint(
                        key: const Key('reactionBinIcon'),
                        size: const Size(28, 30),
                        painter: _BinPainter(
                            open: open,
                            color: Color.lerp(
                                HuntrColors.coral, Colors.white, open)!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// A bin: its can, and its lid tipped open by [open] (0 shut, 1 open).
class _BinPainter extends CustomPainter {
  _BinPainter({required this.open, required this.color});

  final double open;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // the can, narrowing to the bottom, with its ribs
    final can = Path()
      ..moveTo(w * 0.18, h * 0.32)
      ..lineTo(w * 0.26, h * 0.95)
      ..lineTo(w * 0.74, h * 0.95)
      ..lineTo(w * 0.82, h * 0.32);
    canvas.drawPath(can, stroke);
    for (final x in [0.41, 0.59]) {
      canvas.drawLine(Offset(w * x, h * 0.45), Offset(w * x, h * 0.82), stroke);
    }
    // the lid and its handle, hinged at the right and tipped up
    canvas.save();
    canvas.translate(w * 0.92, h * 0.22);
    // up and away from the can (and a little higher)
    canvas.translate(0, -h * 0.06 * open);
    canvas.rotate(0.6 * open);
    canvas.translate(-w * 0.92, -h * 0.22);
    canvas.drawLine(
        Offset(w * 0.08, h * 0.22), Offset(w * 0.92, h * 0.22), stroke);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.38, h * 0.22)
          ..lineTo(w * 0.42, h * 0.08)
          ..lineTo(w * 0.58, h * 0.08)
          ..lineTo(w * 0.62, h * 0.22),
        stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BinPainter old) => old.open != open || old.color != color;
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

/// The heart that pops over a message when it's double tapped: grows in,
/// then fades away.
class _HeartPop extends StatelessWidget {
  const _HeartPop({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: const Key('doubleTapHeart'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 750),
          builder: (context, t, _) {
            // pop in with a little overshoot, hold, fade out
            final scale = t < 0.3
                ? Curves.easeOutBack.transform(t / 0.3)
                : 1.0 + (t - 0.3) * 0.15;
            final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4);
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Text(firstReactionOf(context),
                    style: const TextStyle(fontSize: 46, shadows: [
                      Shadow(color: Colors.black54, blurRadius: 12),
                    ])),
              ),
            );
          },
        ),
      );
}
