import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/huntr_backend.dart';
import '../../theme.dart';
import 'location_bubble.dart';

/// The two people's colours on a shared live map.
Color get myColor => HuntrColors.orange;
const theirColor = HuntrColors.active;

/// A live location sharing request in the chat, and what became of it:
/// asked (Accept / Decline, or Cancel for the one who asked), live (both on
/// a small map; tap to open it, Stop ends it for both), or over and why.
class LiveLocationCard extends StatelessWidget {
  const LiveLocationCard({
    super.key,
    required this.message,
    required this.me,
    required this.other,
    required this.positions,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
    required this.onStop,
    required this.onOpen,
  });

  final ChatMessage message;
  final Profile me;
  final Profile other;
  final LivePositions positions;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;
  final VoidCallback onStop;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final info = message.liveLocation!;
    final mine = message.fromMe;
    final name = other.name.isEmpty ? 'They' : other.name;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.7, 300.0);
    final active = info.active;

    return Align(
      // only as wide as the card where there's room (beside the reply
      // button); a full-width row still puts it on its side
      widthFactor: 1,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: HoverCard(
        key: Key('live-${message.id}'),
        width: width,
        live: active,
        onTap: active ? onOpen : null,
        tapKey: Key('openLive-${message.id}'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (active)
            SizedBox(
              height: 180,
              child: IgnorePointer(
                child: LiveMap(markers: [
                  LiveMarker(
                      person: me, position: positions.me, color: myColor),
                  LiveMarker(
                      person: other,
                      position: positions.them,
                      color: theirColor),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.share_location_rounded,
                    size: 20,
                    color: active || info.pending
                        ? HuntrColors.orange
                        : HuntrColors.muted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Live location',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                _StatusChip(info: info),
              ]),
              const SizedBox(height: 6),
              Text(_describe(info, name),
                  key: const Key('liveText'),
                  style: const TextStyle(
                      color: HuntrColors.muted, fontSize: 13, height: 1.35)),
              ..._actions(info),
            ]),
          ),
        ]),
      ),
    );
  }

  String _describe(LiveLocationInfo info, String name) {
    final byMe = info.endedByMe == true;
    return switch (info.status) {
      'pending' when info.canAccept =>
        '$name wants to share live locations with you. You’ll both see '
            'each other until one of you stops.',
      'pending' => 'Waiting for $name to accept…',
      'active' => 'You’re both sharing live. Tap to open the map.',
      'declined' => byMe ? 'You declined.' : '$name declined.',
      'cancelled' => 'Request cancelled.',
      _ => switch (info.endReason) {
          'offline' =>
            byMe ? 'Ended · you went offline.' : 'Ended · $name went offline.',
          'permission' => byMe
              ? 'Ended · your location access was turned off.'
              : 'Ended · $name’s location access was turned off.',
          _ => byMe ? 'You stopped sharing.' : '$name stopped sharing.',
        },
    };
  }

  List<Widget> _actions(LiveLocationInfo info) {
    if (info.canAccept) {
      return [
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: Key('declineLive-${message.id}'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              onPressed: onDecline,
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: Key('acceptLive-${message.id}'),
              style: FilledButton.styleFrom(
                  backgroundColor: HuntrColors.orange,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder()),
              onPressed: onAccept,
              child: const Text('Accept'),
            ),
          ),
        ]),
      ];
    }
    if (info.canCancel) {
      return [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: Key('cancelLive-${message.id}'),
            onPressed: onCancel,
            child: const Text('Cancel request'),
          ),
        ),
      ];
    }
    if (info.canStop) {
      return [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: Key('stopLiveCard-${message.id}'),
            style: TextButton.styleFrom(foregroundColor: HuntrColors.coral),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            onPressed: onStop,
            label: const Text('Stop'),
          ),
        ),
      ];
    }
    return const [];
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.info});

  final LiveLocationInfo info;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (info.status) {
      'pending' => ('Pending', HuntrColors.orange),
      'active' => ('Live', HuntrColors.online),
      'declined' => ('Declined', HuntrColors.muted),
      'cancelled' => ('Cancelled', HuntrColors.muted),
      _ => ('Ended', HuntrColors.muted),
    };
    return Container(
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
