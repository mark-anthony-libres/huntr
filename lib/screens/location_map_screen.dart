import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/chat/location_bubble.dart';
import '../widgets/chat/media_bubble.dart' show remainingLabel;

/// A shared location on a full-screen map. A live one follows each update
/// as it arrives (the map moves with the pin unless I've panned away).
class LocationMapScreen extends StatefulWidget {
  const LocationMapScreen(
      {super.key, required this.message, required this.name, this.person});

  final ChatMessage message;

  /// Whose location ('You' for mine).
  final String name;

  /// Whose location: their photo is the pin.
  final Profile? person;

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen> {
  final MapController _map = MapController();
  SharedPosition? _shown;
  bool _follow = true;

  @override
  Widget build(BuildContext context) {
    final messaging = MessagingScope.of(context)!;
    final message = widget.message;
    final current = messaging
            .messagesOf(message.conversationId)
            .where((m) => m.id == message.id)
            .firstOrNull ??
        message;
    final position = messaging.positionOf(current);
    final share = current.location!;
    final now = DateTime.now();
    final live = share.live && share.activeAt(now);
    // a live update arrived: keep the pin in view
    if (position != null && !identical(position, _shown)) {
      final first = _shown == null;
      _shown = position;
      if (!first && _follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _map.move(LatLng(position.latitude, position.longitude),
                _map.camera.zoom);
          }
        });
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(share.live ? '${widget.name} · live location' : 'Location',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
              live
                  ? 'Ends in ${remainingLabel(share.endsAt!, now)}'
                      '${position == null ? '' : ' · updated ${_ago(position.at, now)}'}'
                  : share.live
                      ? 'Live location ended'
                      : 'Shared ${_ago(position?.at ?? message.sentAt, now)}',
              style: TextStyle(
                  fontSize: 12,
                  color: live ? HuntrColors.orange : HuntrColors.muted)),
        ]),
      ),
      body: position == null
          ? Center(
              child: Text(share.stopped
                  ? 'They stopped sharing this location.'
                  : 'Waiting for the location…'))
          : Listener(
              // panning by hand stops following
              onPointerDown: (_) => _follow = false,
              child: LocationMap(
                  position: position,
                  person: widget.person,
                  interactive: true,
                  controller: _map),
            ),
      floatingActionButton: position == null
          ? null
          : FloatingActionButton.small(
              tooltip: 'Back to the pin',
              backgroundColor: HuntrColors.surfaceHigh,
              onPressed: () {
                _follow = true;
                _map.move(LatLng(position.latitude, position.longitude), 16);
              },
              child: const Icon(Icons.my_location_rounded,
                  color: HuntrColors.orange),
            ),
    );
  }

  static String _ago(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }
}
