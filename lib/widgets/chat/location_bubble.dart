import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../models/models.dart';
import '../../services/huntr_backend.dart';
import '../avatar.dart';
import '../../theme.dart';
import 'media_bubble.dart' show remainingLabel;

/// OpenStreetMap tiles (free, no key). Loaded only while a map is on
/// screen; the browser or device caches them.
const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// A map of [position], centred on it, with whose it is as the pin (their
/// profile photo), and how precise it is.
class LocationMap extends StatelessWidget {
  const LocationMap(
      {super.key,
      required this.position,
      this.person,
      this.interactive = false,
      this.zoom = 15,
      this.controller});

  final SharedPosition position;

  /// Whose location: their photo is the pin (a plain pin without one).
  final Profile? person;
  final bool interactive;
  final double zoom;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(position.latitude, position.longitude);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: point,
        initialZoom: zoom,
        interactionOptions: InteractionOptions(
            flags: interactive ? InteractiveFlag.all : InteractiveFlag.none),
      ),
      children: [
        TileLayer(urlTemplate: _tiles, userAgentPackageName: 'com.huntr.app'),
        if (position.accuracy != null && position.accuracy! > 0)
          CircleLayer(circles: [
            CircleMarker(
                point: point,
                radius: position.accuracy!,
                useRadiusInMeter: true,
                color: HuntrColors.orange.withValues(alpha: 0.15),
                borderColor: HuntrColors.orange.withValues(alpha: 0.5),
                borderStrokeWidth: 1),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: point,
            width: 56,
            height: 66,
            alignment: Alignment.topCenter,
            child: person == null
                ? const Icon(Icons.location_on_rounded,
                    key: Key('locationPin'),
                    size: 40,
                    color: HuntrColors.orange)
                : PersonPin(person: person!),
          ),
        ]),
        if (interactive) ...[
          const RichAttributionWidget(attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ]),
          const MapZoomButtons(),
        ] else
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Text('© OpenStreetMap',
                  style: TextStyle(fontSize: 9, color: Colors.black54)),
            ),
          ),
      ],
    );
  }
}

/// A shared location in the chat: a small map (tap for full screen), or
/// what's known without a position (it's never stored: after a refresh a
/// one-time location is gone, a live one waits for its next update).
class LocationBubble extends StatelessWidget {
  const LocationBubble({
    super.key,
    required this.message,
    required this.position,
    required this.now,
    required this.onOpen,
    required this.onStop,
    this.person,
  });

  final ChatMessage message;
  final SharedPosition? position;

  /// Whose location (their photo is the pin).
  final Profile? person;
  final DateTime now;
  final VoidCallback onOpen;

  /// Mine and still shared: stop sharing it (live or one-time).
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    final share = message.location!;
    final live = share.live;
    final active = share.activeAt(now);
    final position = this.position;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.66, 280.0);

    final stopped = share.stopped;
    final String status;
    if (stopped) {
      status = me ? 'You stopped sharing' : 'No longer shared';
    } else if (live && active) {
      status = 'Live · ends in ${remainingLabel(share.endsAt!, now)}';
    } else if (live) {
      status = 'Live location ended';
    } else {
      status = 'Shared location';
    }
    final canOpen = !stopped && position != null && (!live || active);
    final canStop = me && !stopped && (!live || active);

    return Align(
      // only as wide as the card where there's room (beside the reply
      // button); a full-width row still puts it on its side
      widthFactor: 1,
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: HoverCard(
        key: Key('location-${message.id}'),
        width: width,
        live: live && active,
        onTap: canOpen ? onOpen : null,
        tapKey: Key('openLocation-${message.id}'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 140,
            child: canOpen
                ? IgnorePointer(
                    child: LocationMap(position: position, person: person))
                : _NoPosition(
                    text: stopped
                        ? 'Location no longer shared'
                        : live && active
                            ? 'Waiting for the location…'
                            : live
                                ? 'Live location ended'
                                : 'Location no longer available'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              Icon(live ? Icons.share_location_rounded : Icons.place_rounded,
                  size: 20,
                  color:
                      live && active ? HuntrColors.orange : HuntrColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(live ? 'Live location' : 'Location',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(status,
                          style: TextStyle(
                              fontSize: 12,
                              color: live && active
                                  ? HuntrColors.orange
                                  : HuntrColors.muted)),
                    ]),
              ),
              if (canStop)
                TextButton(
                  key: Key('stopLive-${message.id}'),
                  style:
                      TextButton.styleFrom(foregroundColor: HuntrColors.coral),
                  onPressed: onStop,
                  child: Text(live ? 'Stop' : 'Stop sharing'),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The card's frame: the whole card opens the map; on a mouse, a pointer
/// and an orange border with a soft shadow show it can be clicked.
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.width,
    required this.live,
    required this.onTap,
    required this.tapKey,
    required this.child,
  });

  final double width;
  final bool live;

  /// Null: nothing to open (no pointer, no hover).
  final VoidCallback? onTap;
  final Key tapKey;
  final Widget child;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final canOpen = widget.onTap != null;
    final hot = canOpen && _hover;
    return MouseRegion(
      cursor: canOpen ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: widget.tapKey,
        // the map inside ignores touches: the whole card opens it
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: HuntrColors.surfaceHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                width: hot ? 1.5 : 1,
                color: hot
                    ? HuntrColors.orange
                    : widget.live
                        ? HuntrColors.orange.withValues(alpha: 0.6)
                        : HuntrColors.border),
            boxShadow: hot
                ? [
                    BoxShadow(
                        color: HuntrColors.orange.withValues(alpha: 0.25),
                        blurRadius: 16,
                        spreadRadius: 1),
                  ]
                : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
      ),
    );
  }
}

class _NoPosition extends StatelessWidget {
  const _NoPosition({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: HuntrColors.glowGradient),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_off_outlined,
              size: 32, color: Colors.white70),
          const SizedBox(height: 8),
          Text(text,
              key: const Key('noPosition'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ]),
      ),
    );
  }
}

/// + and - (pinch, the mouse wheel and double-tap zoom too).
class MapZoomButtons extends StatelessWidget {
  const MapZoomButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final map = MapController.of(context);
    final camera = MapCamera.of(context);
    void zoom(double by) => map.move(camera.center,
        (camera.zoom + by).clamp(camera.minZoom ?? 2, camera.maxZoom ?? 19));
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: HuntrColors.surfaceHigh,
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              key: const Key('zoomIn'),
              tooltip: 'Zoom in',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => zoom(1),
            ),
            const SizedBox(width: 32, child: Divider(height: 1)),
            IconButton(
              key: const Key('zoomOut'),
              tooltip: 'Zoom out',
              icon: const Icon(Icons.remove_rounded),
              onPressed: () => zoom(-1),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Their profile photo in an orange ring, pointing at the spot.
class PersonPin extends StatelessWidget {
  const PersonPin(
      {super.key, required this.person, this.color = HuntrColors.orange});

  final Profile person;

  /// The ring (each person has their own on a shared map).
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(key: const Key('personPin'), children: [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
        ),
        child: ClipOval(
          child: SizedBox(
              width: 48,
              height: 48,
              child: ProfileArt(profile: person, fontSize: 18)),
        ),
      ),
      CustomPaint(size: const Size(14, 8), painter: _PinTip(color)),
    ]);
  }
}

class _PinTip extends CustomPainter {
  _PinTip(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close(),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTip oldDelegate) => oldDelegate.color != color;
}

/// One person on a shared live map: their photo pin, or nothing while
/// their position isn't known.
class LiveMarker {
  const LiveMarker(
      {required this.person, required this.position, required this.color});

  final Profile person;
  final SharedPosition? position;
  final Color color;
}

/// Both people of a live session on one map, framed to show both.
class LiveMap extends StatelessWidget {
  const LiveMap(
      {super.key,
      required this.markers,
      this.interactive = false,
      this.controller});

  final List<LiveMarker> markers;
  final bool interactive;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final known = [
      for (final m in markers)
        if (m.position != null)
          (m, LatLng(m.position!.latitude, m.position!.longitude)),
    ];
    if (known.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: HuntrColors.glowGradient),
        child: Center(
          child: Text('Waiting for locations…',
              key: Key('liveWaiting'), style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    final points = [for (final (_, point) in known) point];
    return FlutterMap(
      // frame again once someone else appears (the small card: whenever
      // someone moves, so both always stay in view)
      key: interactive
          ? ValueKey(points.length)
          : ValueKey(Object.hashAll(points)),
      mapController: controller,
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 15,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(
                coordinates: points,
                // the pins stand above their point
                padding: interactive
                    ? const EdgeInsets.fromLTRB(70, 100, 70, 70)
                    : const EdgeInsets.fromLTRB(30, 72, 30, 12),
                maxZoom: 16)
            : null,
        interactionOptions: InteractionOptions(
            flags: interactive ? InteractiveFlag.all : InteractiveFlag.none),
      ),
      children: [
        TileLayer(urlTemplate: _tiles, userAgentPackageName: 'com.huntr.app'),
        MarkerLayer(markers: [
          for (final (m, point) in known)
            Marker(
              point: point,
              width: 56,
              height: 66,
              alignment: Alignment.topCenter,
              child: PersonPin(person: m.person, color: m.color),
            ),
        ]),
        if (interactive) ...[
          const RichAttributionWidget(attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ]),
          const MapZoomButtons(),
        ] else
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Text('© OpenStreetMap',
                  style: TextStyle(fontSize: 9, color: Colors.black54)),
            ),
          ),
      ],
    );
  }
}
