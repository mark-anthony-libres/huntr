import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';

/// The controls floating over HUNTR's maps (Explore's, Roam's): zoom in
/// and out with how wide the map is, and round buttons.

/// How far a map goes from its middle (km, each way) until the backend
/// says (its MAP_REACH_KM): Explore's map, and Roam's around a place.
const defaultMapReachKm = 50.0;

/// The square [km] each way around [center] (a map kept within it can't be
/// panned or zoomed out past it).
LatLngBounds reachBounds(LatLng center, double km) {
  final lat = km / 111.32;
  final lng = lat / math.max(0.01, math.cos(center.latitude * math.pi / 180));
  return LatLngBounds(LatLng(center.latitude - lat, center.longitude - lng),
      LatLng(center.latitude + lat, center.longitude + lng));
}

/// Zooms [map] in (+) or out (-) by [delta], kept within [min]-[max].
void zoomMapBy(MapController map, double delta,
    {required double min, required double max}) {
  final camera = map.camera;
  map.move(camera.center, (camera.zoom + delta).clamp(min, max).toDouble());
}

/// Metres across a map this [width] (logical pixels) wide at this [zoom]
/// and [latitude] (the web map's projection).
double acrossMetres(double latitude, double zoom, double width) =>
    156543.03392 *
    math.cos(latitude * math.pi / 180) /
    math.pow(2, zoom) *
    width;

/// How far it is across a map this [width] (logical pixels) wide at this
/// [zoom] and [latitude]: "800 m", "3 km", "25 km".
String acrossLabel(double latitude, double zoom, double width) {
  final metres = acrossMetres(latitude, zoom, width);
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  final km = metres / 1000;
  return km < 10
      ? '${km.toStringAsFixed(1).replaceAll('.0', '')} km'
      : '${km.round()} km';
}

/// Zoom in, how wide the map shown is ([across]), zoom out: one card.
class MapZoomCard extends StatelessWidget {
  const MapZoomCard(
      {super.key,
      required this.across,
      required this.onZoomIn,
      required this.onZoomOut});

  /// "3.7 km" (null until the map is ready).
  final String? across;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget button(Key key, String tooltip, IconData icon, VoidCallback tap) =>
        IconButton(
          key: key,
          tooltip: tooltip,
          onPressed: tap,
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            fixedSize: const Size(46, 42),
            shape: const RoundedRectangleBorder(),
          ),
          icon: Icon(icon, size: 22),
        );
    const line = SizedBox(
        width: 26, child: Divider(height: 1, color: HuntrColors.border));
    return Container(
      width: 46,
      clipBehavior: Clip.antiAlias,
      decoration: mapFloating(radius: 23),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        button(const Key('mapZoomIn'), 'Zoom in', Icons.add_rounded, onZoomIn),
        if (across case final text?) ...[
          line,
          Tooltip(
            key: const Key('mapAcross'),
            message: 'Width of the map shown',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                FittedBox(
                  child: Text(text,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5)),
                ),
                const Text('across',
                    style: TextStyle(color: HuntrColors.muted, fontSize: 9)),
              ]),
            ),
          ),
        ],
        line,
        button(const Key('mapZoomOut'), 'Zoom out', Icons.remove_rounded,
            onZoomOut),
      ]),
    );
  }
}

/// Things floating over a map: the app's surface, a hairline edge and a
/// soft shadow.
BoxDecoration mapFloating({required double radius}) => BoxDecoration(
      color: HuntrColors.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: HuntrColors.border),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
      ],
    );

class MapButton extends StatelessWidget {
  const MapButton(
      {super.key,
      required this.tooltip,
      required this.icon,
      required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: mapFloating(radius: 23),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            foregroundColor: HuntrColors.orange,
            fixedSize: const Size(46, 46),
          ),
          icon: Icon(icon, size: 22),
        ),
      );
}

/// A short note over a map ("Locations are approximate"); tapped (with an
/// info mark), more about it.
class MapNote extends StatelessWidget {
  const MapNote(
      {super.key,
      required this.icon,
      required this.text,
      this.error = false,
      this.onTap});

  final IconData icon;
  final String text;
  final bool error;

  /// Tapped: more about it (with a small info mark).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final note = _box();
    if (onTap == null) return note;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          borderRadius: BorderRadius.circular(999), onTap: onTap, child: note),
    );
  }

  Widget _box() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: error
                  ? HuntrColors.coral
                  : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 15, color: error ? HuntrColors.coral : HuntrColors.orange),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.info_outline_rounded,
                size: 15, color: Colors.white70),
          ],
        ]),
      );
}

/// One point of a map's info sheet: an icon, a title and what it means.
class MapInfoPoint extends StatelessWidget {
  const MapInfoPoint(
      {super.key,
      required this.icon,
      required this.title,
      required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: HuntrColors.orange, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(text,
                  style: const TextStyle(
                      color: HuntrColors.muted, fontSize: 14, height: 1.45)),
            ]),
          ),
        ]),
      );
}

/// Where I am (only my own, exact position, to me): a dot in the accent
/// with a soft ring pulsing out of it (still when the device asks for
/// less motion).
class MyLocationDot extends StatefulWidget {
  const MyLocationDot({super.key});

  @override
  State<MyLocationDot> createState() => _MyLocationDotState();
}

class _MyLocationDotState extends State<MyLocationDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = HuntrColors.orange;
    return RepaintBoundary(
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = Curves.easeOut.transform(_pulse.value);
            return Container(
              width: 20 + 44 * t,
              height: 20 + 44 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.28 * (1 - t)),
                border: Border.all(
                    color: accent.withValues(alpha: 0.5 * (1 - t)), width: 1.5),
              ),
            );
          },
        ),
        Container(
          key: const Key('mapMyDot'),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 1),
              const BoxShadow(color: Colors.black54, blurRadius: 4),
            ],
          ),
        ),
      ]),
    );
  }
}
