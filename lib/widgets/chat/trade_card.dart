import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/huntr_backend.dart';
import '../../theme.dart';
import 'media_bubble.dart' show remainingLabel;

/// An album trade in the chat, as cards on each person's side: the offer
/// ("… sent an album trade"), and once it's completed the album chosen in
/// return ("… traded an album"). Covers always stay blurred behind a lock;
/// the album I received is only seen by opening it (View album), which then
/// disappears like chat media. My own albums open in my album screen.
class TradeCard extends StatelessWidget {
  const TradeCard({
    super.key,
    required this.message,
    required this.other,
    required this.now,
    required this.onRespond,
    required this.onCancel,
    required this.onOpenTheirs,
    required this.onOpenMine,
    this.busy = false,
    this.wrapOffer,
  });

  final ChatMessage message;

  /// The other person in the chat.
  final Profile other;
  final DateTime now;
  final VoidCallback onRespond;
  final VoidCallback onCancel;
  final VoidCallback onOpenTheirs;
  final void Function(int albumId) onOpenMine;

  /// A cancel is being sent.
  final bool busy;

  /// Wraps the offer's card (the message itself: reply, its quote); the
  /// album chosen in return is shown as it is.
  final Widget Function(Widget offer)? wrapOffer;

  @override
  Widget build(BuildContext context) {
    final trade = message.trade!;
    final me = trade.fromMe;
    final name = other.name.isEmpty ? 'They' : other.name;
    final completed = trade.status == TradeStatus.completed;
    // the offer: theirs to open once completed, mine to open any time
    final offerTheirs = !me && completed;
    final offerAction =
        me || completed ? _view(trade.offeredAlbum, theirs: offerTheirs) : null;
    final offer = _AlbumCard(
      key: Key('trade-${trade.id}'),
      mine: me,
      who: me ? 'You' : name,
      verb: 'sent an album trade',
      time: message.sentAt,
      album: trade.offeredAlbum,
      status: trade.status,
      coverAction: offerAction,
      footer: [
        if (offerTheirs) ..._countdown(trade.offeredAlbum),
        ..._offerFooter(trade, name),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      wrapOffer?.call(offer) ?? offer,
      if (completed)
        _AlbumCard(
          key: Key('tradeBack-${trade.id}'),
          mine: !me,
          who: me ? name : 'You',
          verb: 'traded an album',
          time: trade.completedAt ?? message.sentAt,
          album: trade.returnedAlbum,
          status: null,
          coverAction: _view(trade.returnedAlbum, theirs: me),
          footer: [if (me) ..._countdown(trade.returnedAlbum)],
        ),
    ]);
  }

  List<Widget> _offerFooter(AlbumTrade trade, String name) {
    switch (trade.status) {
      case TradeStatus.pending when trade.canRespond:
        return [
          _FilledAction(
            key: Key('respondTrade-${trade.id}'),
            label: 'Choose an album',
            onPressed: busy ? null : onRespond,
          ),
          TextButton(
            key: Key('declineTrade-${trade.id}'),
            style: TextButton.styleFrom(foregroundColor: HuntrColors.muted),
            onPressed: busy ? null : onCancel,
            child: const Text('Not now',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ];
      case TradeStatus.pending:
        return [
          Row(children: [
            Expanded(
              child: Text('Waiting for $name to trade back',
                  style:
                      const TextStyle(color: HuntrColors.muted, fontSize: 13)),
            ),
            if (trade.canCancel)
              TextButton(
                key: Key('cancelTrade-${trade.id}'),
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel'),
              ),
          ]),
        ];
      case TradeStatus.completed:
        return const [];
      case TradeStatus.cancelled:
        return const [
          Text('This trade was cancelled',
              style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
        ];
    }
  }

  /// "View album" on the cover: theirs opens (and starts my countdown),
  /// mine opens my album screen; an expired one can't be opened.
  _CoverAction? _view(TradeAlbum? album, {required bool theirs}) {
    if (album == null) return null;
    final trade = message.trade!;
    if (!theirs) {
      return _CoverAction(
          key: Key('openMine-${trade.id}-${album.id}'),
          label: 'View album',
          onTap: () => onOpenMine(album.id));
    }
    if (album.expiredAt(now)) {
      return const _CoverAction(
          key: Key('tradeAlbumExpired'), label: 'Album expired', onTap: null);
    }
    return _CoverAction(
        key: Key('openTheirs-${trade.id}'),
        label: 'View album',
        onTap: onOpenTheirs);
  }

  /// Under their album: how long I can still open it.
  List<Widget> _countdown(TradeAlbum? album) {
    if (album == null || album.expiredAt(now)) return const [];
    final expiresAt = album.expiresAt;
    return [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.timer_outlined, size: 15, color: HuntrColors.muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
              expiresAt == null
                  ? 'Disappears a while after you close it'
                  : 'Disappears in ${remainingLabel(expiresAt, now)}',
              key: const Key('tradeExpiry'),
              style: const TextStyle(color: HuntrColors.muted, fontSize: 12)),
        ),
      ]),
    ];
  }
}

/// What tapping a cover does, shown as a pill in its center.
class _CoverAction {
  const _CoverAction(
      {required this.key, required this.label, required this.onTap});

  final Key key;
  final String label;

  /// Null: shown, but it can't be opened (expired).
  final VoidCallback? onTap;
}

/// One album card, on its sender's side of the chat.
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    super.key,
    required this.mine,
    required this.who,
    required this.verb,
    required this.time,
    required this.album,
    required this.status,
    required this.coverAction,
    required this.footer,
  });

  /// On my side (right).
  final bool mine;
  final String who;
  final String verb;
  final DateTime time;
  final TradeAlbum? album;

  /// Shown while it's not simply completed.
  final TradeStatus? status;

  /// Null: just the lock (nothing to open yet).
  final _CoverAction? coverAction;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final album = this.album;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.72, 340.0);
    return Align(
      // only as wide as the card where there's room (beside the reply
      // button); a full-width row still puts it on its side
      widthFactor: 1,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.swap_horiz_rounded,
                size: 22, color: HuntrColors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: who,
                      style: const TextStyle(
                          color: HuntrColors.orange,
                          fontWeight: FontWeight.w700)),
                  TextSpan(text: ' $verb'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
            Text(_clock(time),
                style: const TextStyle(color: HuntrColors.muted, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                  album == null ? 'Album no longer available' : album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: album == null ? HuntrColors.muted : Colors.white)),
            ),
            if (status == TradeStatus.pending ||
                status == TradeStatus.cancelled) ...[
              const SizedBox(width: 8),
              _StatusChip(status: status!),
            ],
          ]),
          if (album != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(album.contents,
                  style:
                      const TextStyle(color: HuntrColors.muted, fontSize: 14)),
            ),
          const SizedBox(height: 10),
          _Cover(album: album, action: coverAction),
          for (final (i, widget) in footer.indexed) ...[
            SizedBox(height: i == 0 ? 10 : 4),
            widget,
          ],
        ]),
      ),
    );
  }
}

/// The album's cover, wide: always its blurred preview, with the lock, or
/// "View album" in its center when there's something to open.
class _Cover extends StatelessWidget {
  const _Cover({required this.album, required this.action});

  final TradeAlbum? album;
  final _CoverAction? action;

  @override
  Widget build(BuildContext context) {
    final album = this.album;
    final action = this.action;
    final url = (album == null || album.previews.isEmpty)
        ? null
        : album.previews.first.url;
    return GestureDetector(
      onTap: action?.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 2.2,
          child: Stack(fit: StackFit.expand, children: [
            // always underneath: shows if the preview is missing or fails
            const DecoratedBox(
                decoration: BoxDecoration(gradient: HuntrColors.glowGradient)),
            if (url != null)
              Image.network(url,
                  key: const Key('tradeCoverBlurred'),
                  fit: BoxFit.cover,
                  // a plain <img> on web: no CORS needed for the bucket
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink()),
            const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x33000000))),
            Center(
              child: action == null
                  ? Container(
                      key: const Key('tradeLock'),
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0xCC0C0C0F)),
                      child: const Icon(Icons.lock_rounded,
                          color: Colors.white, size: 22),
                    )
                  : _ViewPill(action: action),
            ),
          ]),
        ),
      ),
    );
  }
}

/// An open lock and "View album" (green: it can be opened) in the middle
/// of a cover.
class _ViewPill extends StatelessWidget {
  const _ViewPill({required this.action});

  final _CoverAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    return Material(
      color: const Color(0xD90C0C0F),
      shape: StadiumBorder(
          side: BorderSide(
              color: enabled ? HuntrColors.online : HuntrColors.border,
              width: 1.5)),
      child: InkWell(
        key: action.key,
        customBorder: const StadiumBorder(),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // unlocked: it can be opened
            Icon(enabled ? Icons.lock_open_rounded : Icons.timer_off_outlined,
                key: enabled ? const Key('tradeUnlocked') : null,
                size: 18,
                color: enabled ? HuntrColors.online : HuntrColors.muted),
            const SizedBox(width: 8),
            Text(action.label,
                style: TextStyle(
                    fontFamily: huntrFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? HuntrColors.online : HuntrColors.muted)),
          ]),
        ),
      ),
    );
  }
}

class _FilledAction extends StatelessWidget {
  const _FilledAction(
      {super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : HuntrColors.accentGradient,
        color: onPressed == null ? HuntrColors.surfaceHigh : null,
        borderRadius: const BorderRadius.all(Radius.circular(30)),
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(46),
            textStyle: const TextStyle(
                fontFamily: huntrFontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: onPressed,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TradeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TradeStatus.pending => ('Pending', HuntrColors.orange),
      TradeStatus.completed => ('Completed', HuntrColors.online),
      TradeStatus.cancelled => ('Cancelled', HuntrColors.muted),
    };
    return Container(
      key: const Key('tradeStatus'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// "4:27 PM".
String _clock(DateTime time) {
  final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$h:${time.minute.toString().padLeft(2, '0')} '
      '${time.hour < 12 ? 'AM' : 'PM'}';
}
