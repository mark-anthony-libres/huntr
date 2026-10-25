import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/chat/live_location_card.dart' show myColor, theirColor;
import '../widgets/chat/location_bubble.dart';

/// Both people of a live session on one map, updating as they move, under
/// a banner "You're sharing a live connection" with Stop (ends it for
/// both). When it ends (either stops, or goes offline) the map clears and
/// says so.
class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen(
      {super.key,
      required this.message,
      required this.me,
      required this.other});

  final ChatMessage message;
  final Profile me;
  final Profile other;

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  final MapController _map = MapController();
  bool _stopping = false;

  /// While their position hasn't come, or hasn't changed for a while: asks
  /// for it again now and then (an event may have been missed).
  Timer? _lookAgain;
  DateTime _lookedAt = DateTime.now();

  /// Whose positions were known at the last framing (a new one: frame both).
  int _framed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MessagingScope.read(context)?.refreshLivePositions(widget.message);
      }
    });
    _lookAgain = Timer.periodic(const Duration(seconds: 4), (_) {
      final messaging = MessagingScope.read(context);
      if (!mounted || messaging == null) return;
      final m = _current(messaging);
      final them = messaging.livePositionsOf(m.id!).them;
      final now = DateTime.now();
      // not yet: every few seconds; quiet a while: now and then
      final due = them == null ||
          (now.difference(them.at) > const Duration(seconds: 30) &&
              now.difference(_lookedAt) > const Duration(seconds: 15));
      if (m.liveLocation?.active == true && due) {
        _lookedAt = now;
        messaging.refreshLivePositions(m);
      }
    });
  }

  @override
  void dispose() {
    _lookAgain?.cancel();
    super.dispose();
  }

  /// Someone new on the map (they arrived): both in view.
  void _frameNewcomers(LivePositions positions) {
    final known = [positions.me, positions.them].where((p) => p != null).length;
    if (known <= _framed) return;
    _framed = known;
    if (known < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _fitBoth(positions);
      } catch (_) {
        // the map isn't laid out yet: it frames both itself
      }
    });
  }

  ChatMessage _current(MessagingState messaging) =>
      messaging
          .messagesOf(widget.message.conversationId)
          .where((m) => m.id == widget.message.id)
          .firstOrNull ??
      widget.message;

  Future<void> _stop(MessagingState messaging, ChatMessage m) async {
    setState(() => _stopping = true);
    try {
      await messaging.stopLiveLocation(m);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is BackendException
                ? error.message
                : 'Check your connection and try again.')));
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  /// Tapping a person's chip: the map centred on them (zoomed in to at
  /// least street level).
  void _center(SharedPosition? p) {
    if (p == null) return;
    final zoom = _map.camera.zoom < 15 ? 15.0 : _map.camera.zoom;
    _map.move(LatLng(p.latitude, p.longitude), zoom);
  }

  void _fitBoth(LivePositions positions) {
    final points = [
      for (final p in [positions.me, positions.them])
        if (p != null) LatLng(p.latitude, p.longitude),
    ];
    if (points.length > 1) {
      _map.fitCamera(CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(70, 100, 70, 70),
          maxZoom: 16));
    } else if (points.length == 1) {
      _map.move(points.single, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messaging = MessagingScope.of(context)!;
    final m = _current(messaging);
    final info = m.liveLocation!;
    final positions = messaging.livePositionsOf(m.id!);
    final name = widget.other.name.isEmpty ? 'They' : widget.other.name;
    final now = DateTime.now();
    if (info.active) _frameNewcomers(positions);

    return Scaffold(
      appBar: AppBar(title: Text('Live location with $name')),
      body: Column(children: [
        if (info.active)
          _Banner(
            stopping: _stopping,
            onStop: () => _stop(messaging, m),
          )
        else
          _EndedBanner(info: info, name: name),
        Expanded(
          child: !info.active
              ? const Center(
                  child: Icon(Icons.location_off_outlined,
                      size: 56, color: HuntrColors.muted))
              : Stack(children: [
                  LiveMap(
                    controller: _map,
                    interactive: true,
                    markers: [
                      LiveMarker(
                          person: widget.me,
                          position: positions.me,
                          color: myColor),
                      LiveMarker(
                          person: widget.other,
                          position: positions.them,
                          color: theirColor),
                    ],
                  ),
                  // they accepted, but their position hasn't come yet
                  if (positions.them == null)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Center(child: _WaitingFor(name: name)),
                    ),
                  // frame both again (under the zoom buttons)
                  if (positions.me != null || positions.them != null)
                    Positioned(
                      top: 120,
                      right: 12,
                      child: Material(
                        color: HuntrColors.surfaceHigh,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: IconButton(
                          key: const Key('fitBoth'),
                          tooltip: 'Show both',
                          onPressed: () => _fitBoth(positions),
                          icon: Icon(Icons.zoom_out_map_rounded,
                              color: HuntrColors.orange),
                        ),
                      ),
                    ),
                  // who's where, and who isn't known yet
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      _Who(
                          key: const Key('centerMe'),
                          label: 'You',
                          color: myColor,
                          position: positions.me,
                          now: now,
                          onTap: () => _center(positions.me)),
                      _Who(
                          key: const Key('centerThem'),
                          label: name,
                          color: theirColor,
                          position: positions.them,
                          now: now,
                          onTap: () => _center(positions.them)),
                    ]),
                  ),
                ]),
        ),
      ]),
    );
  }
}

/// "Waiting for Sam's location…": they're in, their phone is still finding
/// where they are (or their connection is slow).
class _WaitingFor extends StatelessWidget {
  const _WaitingFor({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('liveWaitingForThem'),
      padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
      decoration: BoxDecoration(
        color: const Color(0xF20C0C0F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theirColor.withValues(alpha: 0.7)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
            dimension: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: theirColor)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
              name == 'They'
                  ? 'Waiting for their location…'
                  : 'Waiting for $name’s location…',
              maxLines: 2,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// "You're sharing a live connection" and Stop, always at the top.
class _Banner extends StatelessWidget {
  const _Banner({required this.stopping, required this.onStop});

  final bool stopping;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('liveConnectionBanner'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: HuntrColors.orange.withValues(alpha: 0.16),
      child: Row(children: [
        Icon(Icons.share_location_rounded, color: HuntrColors.orange),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('You’re sharing a live connection',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        FilledButton.icon(
          key: const Key('stopLiveConnection'),
          style: FilledButton.styleFrom(
              backgroundColor: HuntrColors.coral,
              foregroundColor: Colors.white,
              shape: const StadiumBorder()),
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Stop'),
          onPressed: stopping ? null : onStop,
        ),
      ]),
    );
  }
}

class _EndedBanner extends StatelessWidget {
  const _EndedBanner({required this.info, required this.name});

  final LiveLocationInfo info;
  final String name;

  @override
  Widget build(BuildContext context) {
    final byMe = info.endedByMe == true;
    final text = switch (info.endReason) {
      'offline' => byMe
          ? 'Live sharing ended because you went offline.'
          : 'Live sharing ended because $name went offline.',
      'permission' => byMe
          ? 'Live sharing ended: your location access was turned off.'
          : 'Live sharing ended: $name’s location access was turned off.',
      _ => info.status == 'ended'
          ? (byMe ? 'You stopped sharing.' : '$name stopped sharing.')
          : 'Live sharing isn’t active.',
    };
    return Container(
      key: const Key('liveEndedBanner'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: HuntrColors.surfaceHigh,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

/// One person's chip: when their position last came, or that it hasn't.
class _Who extends StatelessWidget {
  const _Who(
      {super.key,
      required this.label,
      required this.color,
      required this.position,
      required this.now,
      required this.onTap});

  final String label;
  final Color color;
  final SharedPosition? position;
  final DateTime now;

  /// Centres the map on them (nothing while their position isn't known).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final ago = p == null ? null : now.difference(p.at);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE60C0C0F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(
            p == null
                ? '$label · waiting for location…'
                : '$label · ${ago!.inSeconds < 60 ? 'just now' : '${ago.inMinutes} min ago'}',
            style: const TextStyle(fontSize: 12, color: Colors.white)),
      ]),
    );
    if (p == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: onTap, child: chip),
    );
  }
}
