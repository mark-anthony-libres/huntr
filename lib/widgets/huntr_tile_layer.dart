import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'explore/explore_map.dart' show MapTiles;
import 'night_map.dart';

/// The map images every HUNTR map uses (tests put [MapTiles.none] here).
MapTiles Function() huntrMapTiles = () => MapTiles.configured;

/// A map's images, the same on every HUNTR map (Explore, Roam, a location
/// in chat): [tiles]' sources in order ([MapTiles.inOrder]), going on to
/// the next when one keeps failing (a refused key, a provider down), dark
/// like the app, with their credits. Put it first in a [FlutterMap]'s
/// children.
class HuntrTileLayer extends StatefulWidget {
  const HuntrTileLayer({
    super.key,
    this.tiles,
    this.credits = true,
    this.creditsAt = AttributionAlignment.bottomLeft,
    this.onUnavailable,
  });

  /// The sources (null: [huntrMapTiles]).
  final MapTiles? tiles;

  /// Show the providers' credits (an "i" that opens them).
  final bool credits;
  final AttributionAlignment creditsAt;

  /// None of the sources works (the map has no images): told once.
  final VoidCallback? onUnavailable;

  @override
  State<HuntrTileLayer> createState() => _HuntrTileLayerState();
}

class _HuntrTileLayerState extends State<HuntrTileLayer> {
  /// Which source is used; past the last one, none (they all kept failing).
  int _source = 0;

  /// When images failed lately (since the source last changed).
  final List<DateTime> _failures = [];

  /// This many failed images within [_failureWindow]: the next source.
  static const _failuresToSwitch = 6;
  static const _failureWindow = Duration(seconds: 20);

  /// An image from source [from] failed (late ones from an earlier source
  /// don't count against the next).
  void _failed(int from, int sourceCount) {
    if (from != _source) return;
    final now = DateTime.now();
    _failures
      ..add(now)
      ..removeWhere((at) => now.difference(at) > _failureWindow);
    if (_failures.length < _failuresToSwitch) return;
    _failures.clear();
    // (failures are told while the map draws)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _source != from) return;
      setState(() => _source = from + 1);
      if (_source >= sourceCount) widget.onUnavailable?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sources = (widget.tiles ?? huntrMapTiles()).inOrder;
    final source = _source;
    if (source >= sources.length || sources[source].url.isEmpty) {
      return const SizedBox.shrink();
    }
    final tiles = sources[source];
    final layer = TileLayer(
      // a new layer per source (nothing of the last one kept)
      key: ValueKey('tiles-$source'),
      urlTemplate: tiles.url,
      // a refused image (e.g. MapTiler's "Invalid key" picture, sent with a
      // 403) counts as failed, not drawn: so the next source takes over
      tileProvider:
          NetworkTileProvider(attemptDecodeOfHttpErrorResponses: false),
      errorTileCallback: (tile, error, stack) =>
          _failed(source, sources.length),
      // sharp images on sharp screens, where the provider has them
      retinaMode:
          tiles.url.contains('{r}') && RetinaMode.isHighDensity(context),
      userAgentPackageName: 'com.marklibres.huntr',
      maxNativeZoom: tiles.maxNativeZoom,
    );
    return Stack(children: [
      // drawn on its own: what changes on top (markers) never makes the
      // images draw again; one colour filter for all of them
      RepaintBoundary(child: tiles.night ? nightMap(layer) : layer),
      if (widget.credits && tiles.attributions.isNotEmpty)
        RichAttributionWidget(
          alignment: widget.creditsAt,
          attributions: [
            for (final credit in tiles.attributions)
              TextSourceAttribution(credit),
          ],
        ),
    ]);
  }
}
