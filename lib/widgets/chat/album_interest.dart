import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// After I looked at their album in a trade: asked, only in my own chat,
/// whether I'm interested. Yes tells them (one message); "Not right now"
/// tells nobody. Above the message box, never a message itself; while I
/// ignore it (or hide it with ×) it stays asked, and comes back next time.
class AlbumInterestPrompt extends StatefulWidget {
  const AlbumInterestPrompt(
      {super.key, required this.onAnswer, required this.onHide});

  /// Saves my answer (throws [BackendException] when it couldn't).
  final Future<void> Function(bool interested) onAnswer;

  /// Out of the way for now (nothing is saved).
  final VoidCallback onHide;

  @override
  State<AlbumInterestPrompt> createState() => _AlbumInterestPromptState();
}

class _AlbumInterestPromptState extends State<AlbumInterestPrompt> {
  /// The answer being saved (null: none).
  bool? _saving;
  String? _error;

  Future<void> _answer(bool interested) async {
    if (_saving != null) return;
    setState(() {
      _saving = interested;
      _error = null;
    });
    try {
      await widget.onAnswer(interested);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'That didn’t go through. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = _saving;
    return _Card(
      key: const Key('albumInterestPrompt'),
      onHide: saving == null ? widget.onHide : null,
      children: [
        Icon(Icons.favorite_border_rounded,
            color: HuntrColors.orange, size: 34),
        const SizedBox(height: 8),
        const Text('A little spark? ✨',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
            'You’ve had a look at their album. Want to let them know you’re '
            'interested?',
            textAlign: TextAlign.center,
            style: TextStyle(color: HuntrColors.muted, height: 1.4)),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: ShapeDecoration(
              gradient: HuntrColors.accentGradient,
              shape: const StadiumBorder()),
          child: FilledButton(
            key: const Key('albumInterestYes'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.black54,
              shadowColor: Colors.transparent,
              textStyle: const TextStyle(
                  fontFamily: huntrFontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w800),
            ),
            onPressed: saving == null ? () => _answer(true) : null,
            child: saving == true
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Text('Yes, I’m interested ❤️'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('albumInterestNotNow'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape: const StadiumBorder(),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          ),
          onPressed: saving == null ? () => _answer(false) : null,
          child: saving == false
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Not right now'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              key: const Key('albumInterestError'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: HuntrColors.coral, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: HuntrColors.muted),
          SizedBox(width: 6),
          Flexible(
            child: Text(
                'Your choice stays private. They’ll only know if you choose '
                'to let them know.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HuntrColors.muted, fontSize: 12)),
          ),
        ]),
      ],
    );
  }
}

/// Right after a yes: "You let them know!" for a few seconds (or until ×).
class AlbumInterestSent extends StatefulWidget {
  const AlbumInterestSent({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<AlbumInterestSent> createState() => _AlbumInterestSentState();
}

class _AlbumInterestSentState extends State<AlbumInterestSent> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      key: const Key('albumInterestSent'),
      onHide: widget.onDone,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _sparks(left: true),
          const SizedBox(width: 8),
          Icon(Icons.favorite_rounded, color: HuntrColors.orange, size: 34),
          const SizedBox(width: 8),
          _sparks(left: false),
        ]),
        const SizedBox(height: 10),
        const Text('You let them know!',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('If they’re interested too, you’ll get a message. 😊',
            textAlign: TextAlign.center,
            style: TextStyle(color: HuntrColors.muted, height: 1.4)),
      ],
    );
  }
}

/// Two little strokes beside the heart, leaning out.
Widget _sparks({required bool left}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          left ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final (i, length) in [(0, 9.0), (1, 6.0)])
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 5),
            child: Transform.rotate(
              angle: (left ? 1 : -1) * (i == 0 ? 0.6 : -0.5),
              child: Container(
                  width: length,
                  height: 2.4,
                  decoration: BoxDecoration(
                      color: HuntrColors.orange,
                      borderRadius: BorderRadius.circular(2))),
            ),
          ),
      ],
    );

/// The prompt's rounded card, with a quiet × to put it away.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.children, this.onHide});

  final List<Widget> children;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: HuntrColors.border),
          ),
          child: Stack(children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              // the sheet's little handle, as in the rest of the app
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              ...children,
            ]),
            if (onHide != null)
              Positioned(
                top: -6,
                right: -10,
                child: IconButton(
                  key: const Key('albumInterestHide'),
                  tooltip: 'Hide',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: HuntrColors.muted),
                  onPressed: onHide,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// In the chat: "❤️ Sam is interested in your album!" (to the album's
/// owner), or, to me, that I said so.
class AlbumInterestCard extends StatelessWidget {
  const AlbumInterestCard(
      {super.key, required this.message, required this.otherName});

  final ChatMessage message;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromMe;
    final who = otherName.isEmpty ? 'Someone' : otherName;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: Key('albumInterest-${message.id ?? message.clientId}'),
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: mine
              ? HuntrColors.surface
              : HuntrColors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: HuntrColors.orange.withValues(alpha: mine ? 0.25 : 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: HuntrColors.orange.withValues(alpha: 0.18),
                shape: BoxShape.circle),
            child: Icon(Icons.favorite_rounded,
                color: HuntrColors.orange, size: 19),
          ),
          const SizedBox(width: 10),
          Flexible(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  mine
                      ? 'You’re interested'
                      : '$who is interested in your album!',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (mine) ...[
                const SizedBox(height: 2),
                const Text('They’ll be notified.',
                    style: TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
