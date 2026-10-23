import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../../services/explore_service.dart';
import '../../services/huntr_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../avatar.dart';

/// Explore's map is hidden unless built with MAP_ENABLED=true (env/*.json):
/// no Map button, no "Show me on the map" setting.
const mapEnabled = bool.fromEnvironment('MAP_ENABLED');

/// Where the map's images come from, set when building (env/*.json):
///
/// - MAPTILER_KEY: MapTiler's plain light map, Dataviz (for the live app;
///   restrict the key to HUNTR's domains and app ids in MapTiler's
///   dashboard).
/// - MAP_TILE_URL (+ MAP_TILE_ATTRIBUTION): any other provider.
/// - neither (development): OpenStreetMap's map, made plain. Its rules don't
///   allow it for a live app, so set one of the above for production.
class MapTiles {
  const MapTiles(
      {required this.url, required this.attributions, this.plain = false});

  /// '' for no map images (e.g. tests).
  final String url;
  final List<String> attributions;

  /// A colourful map made plain: no colour, near white.
  final bool plain;

  static const _mapTilerKey = String.fromEnvironment('MAPTILER_KEY');
  static const _customUrl = String.fromEnvironment('MAP_TILE_URL');
  static const _customCredit = String.fromEnvironment('MAP_TILE_ATTRIBUTION');

  static MapTiles get configured {
    if (_customUrl.isNotEmpty) {
      return MapTiles(url: _customUrl, attributions: [
        if (_customCredit.isNotEmpty) _customCredit,
        'OpenStreetMap contributors',
      ]);
    }
    if (_mapTilerKey.isNotEmpty) {
      return const MapTiles(
          url: 'https://api.maptiler.com/maps/dataviz/{z}/{x}/{y}{r}.png'
              '?key=$_mapTilerKey',
          attributions: ['MapTiler', 'OpenStreetMap contributors']);
    }
    return const MapTiles(
        url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        attributions: ['OpenStreetMap contributors'],
        plain: true);
  }

  static const none = MapTiles(url: '', attributions: []);
}

/// Explore as a map: the people in the area on screen, from the backend
/// (never where they really are: it blurs every position to about 500 m),
/// filtered like the list. Zoomed out, small pins (grouped when they'd
/// overlap); zoomed in, their photos. Tap someone for their profile.
class ExploreMap extends StatefulWidget {
  const ExploreMap(
      {super.key, required this.explore, required this.onOpen, this.tiles});

  final ExploreService explore;
  final void Function(Profile person) onOpen;

  /// The map's images (null: as configured, see [MapTiles]).
  final MapTiles? tiles;

  /// Close enough to tell people apart. It reveals nothing: every position
  /// is already blurred by the backend (a fixed spot in a ~500 m square).
  static const minZoom = 10.0;
  static const maxZoom = 18.0;

  /// Photos instead of pins from here in.
  static const photoZoom = 14.0;

  @override
  State<ExploreMap> createState() => _ExploreMapState();
}

class _ExploreMapState extends State<ExploreMap> {
  final _map = MapController();
  List<MapPerson> _people = const [];
  bool _more = false;
  bool _loading = false;
  String? _error;
  Timer? _settle;
  int _asked = 0;

  /// Manila, until my own position is known.
  static const _fallback = LatLng(14.5995, 120.9842);

  LatLng? get _me {
    final mine = AppScope.read(context).myLocation;
    return mine == null ? null : LatLng(mine.latitude, mine.longitude);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Once the map stops moving: the people in what's on screen.
  void _moved() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null || !mounted) return;
    final area = _map.camera.visibleBounds;
    final asked = ++_asked;
    setState(() => _loading = true);
    try {
      final found = await widget.explore.fetchMapArea(token,
          south: area.south,
          west: area.west,
          north: area.north,
          east: area.east);
      if (!mounted || asked != _asked) return; // moved on meanwhile
      setState(() {
        _people = found.people;
        _more = found.more;
        _error = null;
      });
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      if (mounted && asked == _asked) {
        setState(() => _error = error is BackendException
            ? error.message
            : "The map couldn't load. Check your connection.");
      }
    } finally {
      if (mounted && asked == _asked) setState(() => _loading = false);
    }
  }

  /// A group: zoom in to separate them, or (already as close as the map
  /// goes) list them.
  void _openGroup(List<MapPerson> group, LatLng center) {
    final zoom = _map.camera.zoom;
    if (zoom < ExploreMap.maxZoom - 0.01) {
      _map.move(center, math.min(zoom + 2, ExploreMap.maxZoom));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          key: const Key('mapGroupList'),
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('${group.length} people here',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            for (final p in group)
              ListTile(
                key: Key('mapGroup-${p.profile.id}'),
                leading: Avatar(profile: p.profile, size: 44),
                title: Text(p.profile.nameAndAge.isEmpty
                    ? p.profile.shortName
                    : p.profile.nameAndAge),
                subtitle: Text(p.profile.distanceLabel,
                    style: const TextStyle(color: HuntrColors.muted)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  widget.onOpen(p.profile);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _map.move(
        camera.center,
        (camera.zoom + delta)
            .clamp(ExploreMap.minZoom, ExploreMap.maxZoom)
            .toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // the list's filters and chips apply here too
    final shown = [
      for (final p in _people)
        if (app.showsInExplore(p.profile)) p
    ];
    final me = _me;
    final tiles = widget.tiles ?? MapTiles.configured;
    return Stack(children: [
      FlutterMap(
        key: const Key('exploreMap'),
        mapController: _map,
        options: MapOptions(
          initialCenter: me ?? _fallback,
          initialZoom: ExploreMap.photoZoom,
          minZoom: ExploreMap.minZoom,
          maxZoom: ExploreMap.maxZoom,
          backgroundColor: _paper,
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: _load,
          onPositionChanged: (_, __) => _moved(),
        ),
        children: [
          if (tiles.url.isNotEmpty)
            // drawn on its own: what changes on top (markers) never makes
            // the map images draw again; and one colour filter for all of
            // them, not one per image
            RepaintBoundary(
              child: _plainIf(
                tiles.plain,
                TileLayer(
                  urlTemplate: tiles.url,
                  // sharp images on sharp screens, where the provider has
                  // them (never by loading 4x the images)
                  retinaMode: tiles.url.contains('{r}') &&
                      RetinaMode.isHighDensity(context),
                  userAgentPackageName: 'com.marklibres.huntr',
                ),
              ),
            ),
          if (me != null)
            MarkerLayer(markers: [
              Marker(
                point: me,
                width: 22,
                height: 22,
                child: const _MyDot(),
              ),
            ]),
          _PeopleLayer(
            people: shown,
            onOpen: widget.onOpen,
            onGroup: _openGroup,
          ),
          if (tiles.attributions.isNotEmpty)
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                for (final credit in tiles.attributions)
                  TextSourceAttribution(credit),
              ],
            ),
        ],
      ),

      // ---- loading, and what the map shows ----
      if (_loading)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child:
              LinearProgressIndicator(minHeight: 2, color: HuntrColors.orange),
        ),
      Positioned(
        left: 12,
        right: 76,
        top: 10,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _Note(
            key: const Key('mapNote'),
            icon:
                _error != null ? Icons.wifi_off_rounded : Icons.blur_on_rounded,
            text: _error ??
                (_more
                    ? 'Showing the nearest ${shown.length}. Zoom in for more.'
                    : 'Spots are approximate, never exact'),
            error: _error != null,
          ),
        ),
      ),

      // ---- controls ----
      Positioned(
        right: 12,
        bottom: 40,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (me != null) ...[
            _MapButton(
              key: const Key('mapMe'),
              tooltip: 'Around me',
              icon: Icons.my_location_rounded,
              onPressed: () => _map.move(me, ExploreMap.photoZoom),
            ),
            const SizedBox(height: 10),
          ],
          _MapButton(
              key: const Key('mapZoomIn'),
              tooltip: 'Zoom in',
              icon: Icons.add_rounded,
              onPressed: () => _zoomBy(1)),
          const SizedBox(height: 6),
          _MapButton(
              key: const Key('mapZoomOut'),
              tooltip: 'Zoom out',
              icon: Icons.remove_rounded,
              onPressed: () => _zoomBy(-1)),
        ]),
      ),
    ]);
  }
}

/// The people, as pins or photos, grouped where they'd overlap on screen
/// (tap a group to zoom in on it, or list it).
class _PeopleLayer extends StatelessWidget {
  const _PeopleLayer(
      {required this.people, required this.onOpen, required this.onGroup});

  final List<MapPerson> people;
  final void Function(Profile) onOpen;
  final void Function(List<MapPerson> group, LatLng center) onGroup;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final photos = camera.zoom >= ExploreMap.photoZoom;
    // one marker per screen cell: closer than this, they'd overlap
    final cell = photos ? 54.0 : 30.0;
    final groups = <(int, int), List<MapPerson>>{};
    for (final p in people) {
      final at = camera.projectAtZoom(LatLng(p.latitude, p.longitude));
      groups.putIfAbsent((at.dx ~/ cell, at.dy ~/ cell), () => []).add(p);
    }
    return MarkerLayer(markers: [
      for (final group in groups.values)
        if (group.length == 1)
          Marker(
            key: Key('mapPerson-${group.single.profile.id}'),
            point: LatLng(group.single.latitude, group.single.longitude),
            width: photos ? 48 : 18,
            height: photos ? 48 : 18,
            child: GestureDetector(
              onTap: () => onOpen(group.single.profile),
              child: photos
                  ? _PhotoMarker(profile: group.single.profile)
                  : _Pin(profile: group.single.profile),
            ),
          )
        else
          _cluster(group, photos: photos),
    ]);
  }

  /// A group's marker: its key is its own (the first person in it), as no
  /// two markers may share one.
  Marker _cluster(List<MapPerson> group, {required bool photos}) {
    final center = LatLng(
      group.map((p) => p.latitude).reduce((a, b) => a + b) / group.length,
      group.map((p) => p.longitude).reduce((a, b) => a + b) / group.length,
    );
    if (photos) {
      // zoomed in: their faces, stacked, and how many
      return Marker(
        key: Key('mapCluster-${group.first.profile.id}'),
        point: center,
        width: 76,
        height: 52,
        child: GestureDetector(
          onTap: () => onGroup(group, center),
          child: _FaceStack(group: group),
        ),
      );
    }
    final size = (30 + 6 * math.log(group.length)).clamp(30, 56).toDouble();
    return Marker(
      key: Key('mapCluster-${group.first.profile.id}'),
      point: center,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => onGroup(group, center),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: HuntrColors.accentGradient,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: HuntrColors.orange.withValues(alpha: 0.4),
                  blurRadius: 10),
            ],
          ),
          child: Text(group.length > 99 ? '99+' : '${group.length}',
              style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
      ),
    );
  }
}

/// A group, zoomed in: two of their faces overlapping, and the count.
class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.group});

  final List<MapPerson> group;

  @override
  Widget build(BuildContext context) {
    Widget face(Profile p) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
          ),
          child: Avatar(
              profile: p, size: 42, showOnline: false, animateStory: false),
        );
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: 22, top: 0, child: face(group[1].profile)),
      Positioned(left: 0, top: 4, child: face(group[0].profile)),
      Positioned(
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            gradient: HuntrColors.accentGradient,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Text('${group.length}',
              key: const Key('mapClusterCount'),
              style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ),
      ),
    ]);
  }
}

/// Zoomed out: a small dot - green online, orange with a story, else grey.
class _Pin extends StatelessWidget {
  const _Pin({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final color = profile.online
        ? HuntrColors.online
        : profile.hasStory && !profile.storySeen
            ? HuntrColors.orange
            : const Color(0xFF6B6F7A);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// Zoomed in: their photo (with the online dot and story ring).
class _PhotoMarker extends StatelessWidget {
  const _PhotoMarker({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: profile.hasStory
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.85), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
        // a still ring: dozens of spinning ones would redraw the whole map
        // every frame
        child: Avatar(profile: profile, size: 48, animateStory: false),
      );
}

/// Where I am (only my own, exact position, to me).
class _MyDot extends StatelessWidget {
  const _MyDot();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('mapMyDot'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: HuntrColors.orange,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
                color: HuntrColors.orange.withValues(alpha: 0.6),
                blurRadius: 12,
                spreadRadius: 2),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(
      {super.key, required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
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
        ]),
      );
}

class _MapButton extends StatelessWidget {
  const _MapButton(
      {super.key,
      required this.tooltip,
      required this.icon,
      required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: HuntrColors.surface,
          foregroundColor: Colors.white,
          side: const BorderSide(color: HuntrColors.border),
          fixedSize: const Size(46, 46),
        ),
        icon: Icon(icon),
      );
}

/// The map's ground while images load.
const _paper = Color(0xFFF4F5F7);

/// A colourful map made plain ([plain]): grey, then lightened to near
/// white, so streets stay readable and people stand out.
Widget _plainIf(bool plain, Widget map) => !plain
    ? map
    : ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.12, 0.38, 0.04, 0, 118, //
          0.12, 0.38, 0.04, 0, 118, //
          0.12, 0.38, 0.04, 0, 120, //
          0, 0, 0, 1, 0,
        ]),
        child: map,
      );
