import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'explore/explore_map.dart' show ExploreMap, MapTiles;
import 'huntr_tile_layer.dart';
import 'map_controls.dart';

/// HUNTR's map, the same everywhere (Explore, Roam, where someone roams, a
/// location in chat): the app's night behind it, its images
/// ([HuntrTileLayer]: the backup source when one keeps failing, and their
/// credits), no turning, Explore's zoom range by default, and (when it can
/// be moved) the zoom card with how wide the map is, at the bottom right,
/// under any [buttons]. [layers] go over the images (pins, people);
/// [overlays] over the map, under the controls (notes, fades).
class HuntrMap extends StatefulWidget {
  const HuntrMap({
    super.key,
    required this.center,
    this.controller,
    this.zoom = ExploreMap.photoZoom,
    this.minZoom = ExploreMap.minZoom,
    this.maxZoom = ExploreMap.maxZoom,
    this.fit,
    this.cameraConstraint,
    this.interactive = true,
    this.zoomControls = true,
    this.controlsBottom = 16,
    this.buttons = const [],
    this.layers = const [],
    this.overlays = const [],
    this.tiles,
    this.credits = true,
    this.creditsAt = AttributionAlignment.bottomLeft,
    this.onUnavailable,
    this.onReady,
    this.onMoved,
    this.onEvent,
    this.onTap,
  });

  final LatLng center;

  /// To move it from outside (null: its own).
  final MapController? controller;
  final double zoom;
  final double minZoom;
  final double maxZoom;

  /// Shows these instead of [center] and [zoom] (e.g. two people).
  final CameraFit? fit;
  final CameraConstraint? cameraConstraint;

  /// Moved and zoomed by hand (a preview in a bubble isn't).
  final bool interactive;

  /// Zoom in / out (with how wide the map is), when [interactive].
  final bool zoomControls;
  final double controlsBottom;

  /// Round buttons above the zoom card ([MapButton]s).
  final List<Widget> buttons;
  final List<Widget> layers;
  final List<Widget> overlays;

  /// The images' sources (null: [huntrMapTiles]).
  final MapTiles? tiles;
  final bool credits;
  final AttributionAlignment creditsAt;

  /// None of the sources works.
  final VoidCallback? onUnavailable;
  final ValueChanged<MapCamera>? onReady;
  final ValueChanged<MapCamera>? onMoved;
  final void Function(MapEvent event)? onEvent;
  final VoidCallback? onTap;

  @override
  State<HuntrMap> createState() => _HuntrMapState();
}

class _HuntrMapState extends State<HuntrMap> {
  MapController? _own;
  MapController get _map => widget.controller ?? (_own ??= MapController());

  /// How wide the map shown is ("3.7 km"), on the zoom card.
  String? _across;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _showAcross(MapCamera camera) {
    if (!widget.interactive || !widget.zoomControls) return;
    final across = acrossLabel(
        camera.center.latitude, camera.zoom, camera.nonRotatedSize.width);
    if (across != _across) setState(() => _across = across);
  }

  void _zoomBy(double delta) =>
      zoomMapBy(_map, delta, min: widget.minZoom, max: widget.maxZoom);

  @override
  Widget build(BuildContext context) {
    final controls = widget.interactive && widget.zoomControls;
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: widget.center,
          initialZoom: widget.zoom,
          initialCameraFit: widget.fit,
          minZoom: widget.minZoom,
          maxZoom: widget.maxZoom,
          cameraConstraint:
              widget.cameraConstraint ?? const CameraConstraint.unconstrained(),
          backgroundColor: HuntrColors.night,
          interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none),
          onMapReady: () {
            _showAcross(_map.camera);
            widget.onReady?.call(_map.camera);
          },
          onPositionChanged: (camera, _) {
            _showAcross(camera);
            widget.onMoved?.call(camera);
          },
          onMapEvent: widget.onEvent,
          onTap: widget.onTap == null ? null : (_, __) => widget.onTap!(),
        ),
        children: [
          HuntrTileLayer(
            tiles: widget.tiles,
            credits: widget.credits,
            creditsAt: widget.creditsAt,
            onUnavailable: widget.onUnavailable,
          ),
          ...widget.layers,
        ],
      ),
      ...widget.overlays,
      if (controls || widget.buttons.isNotEmpty)
        Positioned(
          right: 12,
          bottom: widget.controlsBottom,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final button in widget.buttons) ...[
              button,
              const SizedBox(height: 10),
            ],
            if (controls)
              MapZoomCard(
                across: _across,
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
              ),
          ]),
        ),
    ]);
  }
}
