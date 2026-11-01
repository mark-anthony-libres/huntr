import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart' show BackendException;
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../chat/sticker_image.dart';

/// The stickers people sent this person in chat, each with how many sent
/// it (never who), most first (the top 3 glow and sparkle, when there are
/// more than 3), in a carousel: when they don't all fit they
/// glide by without stopping, starting over seamlessly after the last
/// (the row repeats); holding or swiping it pauses it. See all opens the
/// whole collection. Titled "What people say" (my own profile's preview
/// too). The profile only shows it when there are some; the backend counts
/// only active stickers, and none between two people where one blocks the
/// other.
class StickerShelf extends StatefulWidget {
  const StickerShelf({super.key, required this.userId, required this.stickers});

  final int userId;
  final List<StickerCount> stickers;

  @override
  State<StickerShelf> createState() => _StickerShelfState();
}

class _StickerShelfState extends State<StickerShelf>
    with SingleTickerProviderStateMixin {
  static const _gap = 10.0;

  /// How fast the carousel glides, in logical pixels a second.
  static const _speed = 32.0;

  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_glide);
  Duration _last = Duration.zero;

  /// The width of one pass over the stickers (0: they all fit, no carousel).
  double _loop = 0;

  /// A finger on it (it waits until let go).
  bool _held = false;

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Runs while there's something to glide to and animations are on.
  void _sync() {
    if (!mounted) return;
    final run = _loop > 0 && !MediaQuery.of(context).disableAnimations;
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _glide(Duration elapsed) {
    final step = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_held || !_scroll.hasClients || _loop <= 0) return;
    var next = _scroll.offset + _speed * step;
    // the repeat lines up with the start: jump back unseen
    if (next >= _loop) next -= _loop;
    _scroll.jumpTo(next.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId, stickers = mostSentFirst(widget.stickers);
    const title = stickerSectionTitle;
    return Padding(
      key: const Key('stickerShelf'),
      // as the profile's other sections
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.textsms_outlined,
                color: HuntrColors.orange, size: 26),
          ),
          const SizedBox(width: 12),
          // the title wraps rather than running into See all
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  key: const Key('stickerShelfTitle'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              const Text('Stickers from other users',
                  style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('stickersSeeAll'),
            style: TextButton.styleFrom(
                foregroundColor: HuntrColors.orange,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => showStickerCollection(context, userId,
                title: title, initial: stickers),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('See all', style: TextStyle(fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        // cards of one width (about three and a half across a phone, at
        // most 112 wide), as tall as the longest name needs (names wrap,
        // shown in full)
        LayoutBuilder(builder: (context, constraints) {
          final width =
              ((constraints.maxWidth - 3 * _gap) / 3.5).clamp(84.0, 112.0);
          final pass = stickers.length * (width + _gap);
          // more than fit: a carousel, the row twice so it loops unbroken
          final loop = pass - _gap > constraints.maxWidth ? pass : 0.0;
          if (loop != _loop) {
            _loop = loop;
            if (loop == 0 && _scroll.hasClients) _scroll.jumpTo(0);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
          return Listener(
            onPointerDown: (_) => _held = true,
            onPointerUp: (_) => _held = false,
            onPointerCancel: (_) => _held = false,
            child: SingleChildScrollView(
              key: const Key('stickerCarousel'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              // room for the top 3's glow and sparkles
              padding: const EdgeInsets.symmetric(vertical: 10),
              clipBehavior: Clip.none,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final copy in [false, if (loop > 0) true])
                      for (final (i, sticker) in stickers.indexed) ...[
                        if (copy || i > 0) const SizedBox(width: _gap),
                        SizedBox(
                            width: width,
                            // the repeat: only there to look unbroken
                            child: copy
                                ? ExcludeSemantics(
                                    child: _StickerCard(
                                        sticker: sticker,
                                        rank: topRank(i, stickers.length),
                                        repeat: true))
                                : _StickerCard(
                                    sticker: sticker,
                                    rank: topRank(i, stickers.length))),
                      ],
                  ],
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

/// The section's title, on every profile (mine too).
const stickerSectionTitle = 'What people say';

/// The stickers by how many people sent each, most first (ties keep the
/// server's order).
List<StickerCount> mostSentFirst(List<StickerCount> stickers) {
  final indexed = [...stickers.indexed]..sort((a, b) => b.$2.count != a.$2.count
      ? b.$2.count.compareTo(a.$2.count)
      : a.$1.compareTo(b.$1));
  return [for (final (_, sticker) in indexed) sticker];
}

/// The place (1 to 3) of the sticker at [index] of [total] (most sent
/// first) among the top 3, which glow; none when there are 3 or fewer.
int? topRank(int index, int total) => total > 3 && index < 3 ? index + 1 : null;

/// One kind of sticker with how many sent it: the sticker big (a square of
/// the width it's given), its name in full (wrapping), then the count
/// (people, never who) at the bottom of however tall it's made.
class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.sticker, this.rank, this.repeat = false});

  final StickerCount sticker;

  /// Its place among the top 3 (they glow), or null.
  final int? rank;

  /// The carousel's second copy (its own key).
  final bool repeat;

  @override
  Widget build(BuildContext context) => switch (rank) {
        final rank? => _TopGlow(rank: rank, child: _card()),
        null => _card(),
      };

  Widget _card() => Container(
        key: Key('stickerCount${repeat ? '-repeat' : ''}-${sticker.id}'),
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                AspectRatio(
                  aspectRatio: 1,
                  child:
                      StickerImage(url: sticker.imageUrl, name: sticker.name),
                ),
                const SizedBox(height: 6),
                Text(sticker.name,
                    key: repeat ? null : Key('stickerName-${sticker.id}'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Semantics(
                label: '${sticker.count} '
                    '${sticker.count == 1 ? 'person' : 'people'}',
                excludeSemantics: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_alt_rounded,
                      size: 14, color: HuntrColors.muted),
                  const SizedBox(width: 4),
                  Text('${sticker.count}',
                      style: const TextStyle(
                          color: HuntrColors.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
      );
}

/// A top 3 sticker: a glow that breathes, a shine running around its edge,
/// sparkles twinkling at its corners, and its place (gold, silver, bronze).
/// Still, glowing, when animations are turned off.
class _TopGlow extends StatefulWidget {
  const _TopGlow({required this.rank, required this.child});

  final int rank;
  final Widget child;

  static const _colors = [
    Color(0xFFFFC94D),
    Color(0xFFD9E0EC),
    Color(0xFFE59A5E),
  ];

  @override
  State<_TopGlow> createState() => _TopGlowState();
}

class _TopGlowState extends State<_TopGlow>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spin
        ..stop()
        ..value = 0.25;
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _TopGlow._colors[widget.rank - 1];
    return Semantics(
      label: 'Top ${widget.rank}',
      // as tall as the row makes it, like the other cards
      child:
          Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
        AnimatedBuilder(
          animation: _spin,
          builder: (context, child) {
            final pulse = 0.5 - 0.5 * math.cos(2 * math.pi * _spin.value);
            return CustomPaint(
              foregroundPainter: _GlowPainter(_spin.value, color),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.25 + 0.3 * pulse),
                        blurRadius: 8 + 10 * pulse,
                        spreadRadius: 0.5 + pulse),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
        Positioned(
          key: Key('stickerRank-${widget.rank}'),
          top: -6,
          left: -6,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: HuntrColors.night, width: 2),
            ),
            child: Text('${widget.rank}',
                style: const TextStyle(
                    color: HuntrColors.night,
                    fontSize: 11,
                    fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
    );
  }
}

/// The shine running around a top sticker's edge, and its sparkles.
class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t, this.color);

  /// Where the animation is, 0 to 1 (it repeats).
  final double t;
  final Color color;

  /// Where the sparkles sit (fractions of the card), each twinkling in turn.
  static const _sparkles = [
    Offset(0.92, 0.04),
    Offset(0.06, 0.62),
    Offset(0.96, 0.78),
    Offset(0.5, -0.02),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge =
        RRect.fromRectAndRadius(rect.deflate(0.75), const Radius.circular(18));
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0.35),
            Colors.white,
            color,
            color.withValues(alpha: 0.35),
          ],
          stops: const [0, 0.12, 0.3, 1],
          transform: GradientRotation(2 * math.pi * t),
        ).createShader(rect),
    );
    for (final (i, at) in _sparkles.indexed) {
      final phase = (t + i / _sparkles.length) % 1;
      final glint = math.sin(math.pi * phase); // up, then down again
      if (glint < 0.05) continue;
      final c = Offset(at.dx * size.width, at.dy * size.height);
      final r = 3 + 4 * glint;
      final star = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(
          star,
          Paint()
            ..color =
                Color.lerp(color, Colors.white, 0.6)!.withValues(alpha: glint)
            ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5));
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t || old.color != color;
}

/// All the stickers on someone's profile, fresh from the server (what came
/// with the profile shows meanwhile).
Future<void> showStickerCollection(BuildContext context, int userId,
        {required String title, List<StickerCount> initial = const []}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child:
            _StickerCollection(userId: userId, title: title, initial: initial),
      ),
    );

class _StickerCollection extends StatefulWidget {
  const _StickerCollection(
      {required this.userId, required this.title, required this.initial});

  final int userId;
  final String title;
  final List<StickerCount> initial;

  @override
  State<_StickerCollection> createState() => _StickerCollectionState();
}

class _StickerCollectionState extends State<_StickerCollection> {
  late List<StickerCount> _stickers = widget.initial;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final explore = ServicesScope.exploreOf(context);
    final token = AppScope.read(context).sessionToken;
    if (explore == null || token == null) return;
    try {
      final fresh = await explore.fetchStickers(token, widget.userId);
      if (mounted) setState(() => _stickers = fresh);
    } catch (error) {
      if (mounted && _stickers.isEmpty) {
        setState(() => _error = error is BackendException
            ? error.message
            : "Stickers couldn't load. Check your connection.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(widget.title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
              'Stickers people sent in chat, and how many sent each. '
              "Just for fun: they're reactions, not facts.",
              style: TextStyle(color: HuntrColors.muted, height: 1.4)),
        ),
        Expanded(
          child: _stickers.isEmpty
              ? Center(
                  child: Text(
                      _error ?? 'No stickers yet — be the first to send one.',
                      style: const TextStyle(color: HuntrColors.muted)))
              // even rows: cards of one width, each row as tall as its
              // tallest name, so the counts line up at the bottom (room
              // around them for the top 3's glow and place)
              : SingleChildScrollView(
                  key: const Key('stickerCollection'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: LayoutBuilder(builder: (context, box) {
                    const gap = 12.0;
                    final across = math.max(
                        1, ((box.maxWidth + gap) / (100 + gap)).ceil());
                    final sorted = mostSentFirst(_stickers);
                    return Column(children: [
                      for (var start = 0;
                          start < sorted.length;
                          start += across) ...[
                        if (start > 0) const SizedBox(height: gap),
                        IntrinsicHeight(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = start;
                                    i < start + across;
                                    i++) ...[
                                  if (i > start) const SizedBox(width: gap),
                                  // a short last row keeps the same widths
                                  Expanded(
                                    child: i < sorted.length
                                        ? _StickerCard(
                                            sticker: sorted[i],
                                            rank: topRank(i, sorted.length))
                                        : const SizedBox(),
                                  ),
                                ],
                              ]),
                        ),
                      ],
                    ]);
                  }),
                ),
        ),
      ]),
    );
  }
}
