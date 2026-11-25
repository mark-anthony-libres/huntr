import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../theme.dart';

/// The controls floating over HUNTR's maps (Explore's, Roam's): zoom in
/// and out with how wide the map is, and round buttons.

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
