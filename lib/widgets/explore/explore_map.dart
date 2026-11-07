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
/// - MAPTILER_KEY: MapTiler's plain dark map, Dataviz Dark (for the live app;
///   restrict the key to HUNTR's domains and app ids in MapTiler's
///   dashboard).
/// - MAP_TILE_URL (+ MAP_TILE_ATTRIBUTION): any other provider.
/// - neither (development): OpenStreetMap's map, made dark in the app's
///   accent. Its rules don't
///   allow it for a live app, so set one of the above for production.
class MapTiles {
  const MapTiles(
      {required this.url, required this.attributions, this.night = false});

  /// '' for no map images (e.g. tests).
  final String url;
  final List<String> attributions;

  /// A light, colourful map made dark like the app: near black, with
  /// streets' names and water in the accent.
  final bool night;

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
          url: 'https://api.maptiler.com/maps/dataviz-dark/{z}/{x}/{y}{r}.png'
              '?key=$_mapTilerKey',
          attributions: ['MapTiler', 'OpenStreetMap contributors']);
    }
    return const MapTiles(
        url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        attributions: ['OpenStreetMap contributors'],
        night: true);
  }

  static const none = MapTiles(url: '', attributions: []);
}

/// Explore as a map: the people in the area on screen, from the backend
/// (never where they really are: it blurs every position to about 500 m),
/// filtered like the list. Each person is HUNTR's mark (grouped when they'd
/// overlap, bigger zoomed in; no photos: the map loads none). Tap
/// someone for their profile.
class ExploreMap extends StatefulWidget {
  const ExploreMap(
      {super.key,
      required this.explore,
      required this.onOpen,
      this.tiles,
      this.controlsBottom = 40});

  /// How far up from the bottom the zoom buttons sit (clear of anything
  /// floating there).
  final double controlsBottom;

  final ExploreService explore;
  final void Function(Profile person) onOpen;

  /// The map's images (null: as configured, see [MapTiles]).
  final MapTiles? tiles;

  /// Close enough to tell people apart. It reveals nothing: every position
  /// is already blurred by the backend (a fixed spot in a ~500 m square).
  static const minZoom = 10.0;
  static const maxZoom = 21.0;

  /// The closest the map images go; closer in, those are enlarged.
  static const tileMaxZoom = 19;

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

  /// How wide the map on screen is, between the zoom buttons ("3 km").
  String? _across;

  /// How far from me the map goes (km, each way) and under how wide it
  /// shows photos (metres): the backend's settings, from its answer (until
  /// then the map isn't held in; the backend keeps to them anyway).
  double? _reachKm;
  double? _photosWithinMeters;

  /// What the last answer covers (more than the screen showed), whether it
  /// came with photos, and when: while the map stays inside it, nothing is
  /// asked again.
  LatLngBounds? _fetched;
  bool _fetchedClose = false;
  DateTime? _fetchedAt;

  /// After this, moving the map asks again (who's online changes).
  static const _fresh = Duration(seconds: 60);

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

  /// The square [km] around me.
  static LatLngBounds _reach(LatLng me, double km) {
    final lat = km / 111.32;
    final lng = lat / math.max(0.01, math.cos(me.latitude * math.pi / 180));
    return LatLngBounds(LatLng(me.latitude - lat, me.longitude - lng),
        LatLng(me.latitude + lat, me.longitude + lng));
  }

  /// Once the map stops moving: the people in what's on screen. Meanwhile,
  /// how wide it is.
  void _moved(MapCamera camera) {
    _showAcross(camera);
    _settle?.cancel();
    if (_covered(camera)) return; // the last answer already has it
    _settle = Timer(const Duration(milliseconds: 400), _load);
  }

  /// How wide the map shown is, between the zoom buttons.
  void _showAcross(MapCamera camera) {
    final across = acrossLabel(
        camera.center.latitude, camera.zoom, camera.nonRotatedSize.width);
    if (across != _across) setState(() => _across = across);
  }

  /// Close enough in for photos (under the backend's width for them).
  bool _close(MapCamera camera) {
    final within = _photosWithinMeters;
    return within != null &&
        acrossMetres(camera.center.latitude, camera.zoom,
                camera.nonRotatedSize.width) <
            within;
  }

  /// The last answer still holds for this view: it's inside what was
  /// fetched, recent, not cut short (more people than it could send), and
  /// as close in (photos or not).
  bool _covered(MapCamera camera) {
    final fetched = _fetched, at = _fetchedAt;
    return fetched != null &&
        at != null &&
        !_more &&
        _error == null &&
        DateTime.now().difference(at) < _fresh &&
        _close(camera) == _fetchedClose &&
        fetched.containsBounds(camera.visibleBounds);
  }

  /// The view and as much again around it (half on each side), so small
  /// moves and zooming in need nothing new.
  static LatLngBounds _padded(LatLngBounds view) {
    final lat = (view.north - view.south) / 2;
    final lng = (view.east - view.west) / 2;
    return LatLngBounds(
      LatLng(math.max(-90, view.south - lat), math.max(-180, view.west - lng)),
      LatLng(math.min(90, view.north + lat), math.min(180, view.east + lng)),
    );
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null || !mounted) return;
    final camera = _map.camera;
    // close in (photos), exactly the view: the backend sends photos by how
    // wide the area asked for is; otherwise more than it, to reuse
    final close = _close(camera);
    final area = close ? camera.visibleBounds : _padded(camera.visibleBounds);
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
        _reachKm = found.reachKm ?? _reachKm;
        _photosWithinMeters = found.photosWithinMeters ?? _photosWithinMeters;
        _error = null;
        _fetched = area;
        _fetchedClose = close;
        _fetchedAt = DateTime.now();
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

  /// A group: zoom in as close as all of them still fit on screen (with
  /// room for their markers and the controls), so they spread out as far
  /// as they can; already there, list them.
  void _openGroup(List<MapPerson> group, LatLng center) {
    final camera = _map.camera;
    final fit = CameraFit.coordinates(
      coordinates: [for (final p in group) LatLng(p.latitude, p.longitude)],
      padding: const EdgeInsets.fromLTRB(56, 72, 88, 96),
      maxZoom: ExploreMap.maxZoom,
    ).fit(camera);
    if (fit.zoom > camera.zoom + 0.01) {
      _map.move(fit.center, fit.zoom);
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
                leading: _MarkMarker(profile: p.profile, size: 44),
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
          // all of what's shown stays within the backend's reach of me: no
          // panning past it, and no zooming out wider than it (the backend
          // cuts any area asked for to it, too)
          cameraConstraint: switch ((me, _reachKm)) {
            (final me?, final km?) =>
              CameraConstraint.contain(bounds: _reach(me, km)),
            _ => const CameraConstraint.unconstrained(),
          },
          initialZoom: ExploreMap.photoZoom,
          minZoom: ExploreMap.minZoom,
          maxZoom: ExploreMap.maxZoom,
          backgroundColor: HuntrColors.night,
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () {
            _showAcross(_map.camera);
            _load();
          },
          onPositionChanged: (camera, _) => _moved(camera),
        ),
        children: [
          if (tiles.url.isNotEmpty)
            // drawn on its own: what changes on top (markers) never makes
            // the map images draw again; and one colour filter for all of
            // them, not one per image
            RepaintBoundary(
              child: _nightIf(
                tiles.night,
                TileLayer(
                  urlTemplate: tiles.url,
                  // sharp images on sharp screens, where the provider has
                  // them (never by loading 4x the images)
                  retinaMode: tiles.url.contains('{r}') &&
                      RetinaMode.isHighDensity(context),
                  userAgentPackageName: 'com.marklibres.huntr',
                  maxNativeZoom: ExploreMap.tileMaxZoom,
                ),
              ),
            ),
          if (me != null)
            MarkerLayer(markers: [
              Marker(
                point: me,
                width: 64,
                height: 64,
                child: const _MyDot(),
              ),
            ]),
          _PeopleLayer(
            people: shown,
            photosWithinMeters: _photosWithinMeters,
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

      // ---- soft edges: the map fades into the header and the tabs ----
      const Positioned(left: 0, right: 0, top: 0, child: _Fade(fromTop: true)),
      const Positioned(
          left: 0, right: 0, bottom: 0, child: _Fade(fromTop: false)),

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
                    : 'Locations are approximate'),
            error: _error != null,
          ),
        ),
      ),

      // ---- controls ----
      Positioned(
        right: 12,
        bottom: widget.controlsBottom,
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
          _ZoomCard(
            across: _across,
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
          ),
        ]),
      ),
    ]);
  }
}

/// The people, as HUNTR's mark, grouped where they'd overlap on screen
/// (tap a group to zoom in on it, or list it).
class _PeopleLayer extends StatelessWidget {
  const _PeopleLayer(
      {required this.people,
      required this.photosWithinMeters,
      required this.onOpen,
      required this.onGroup});

  final List<MapPerson> people;

  /// Narrower than this across, their photos (null: not known yet).
  final double? photosWithinMeters;
  final void Function(Profile) onOpen;
  final void Function(List<MapPerson> group, LatLng center) onGroup;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final photos = camera.zoom >= ExploreMap.photoZoom;
    // close in: their photos (the backend sends them only then)
    final within = photosWithinMeters;
    final faces = within != null &&
        acrossMetres(camera.center.latitude, camera.zoom,
                camera.nonRotatedSize.width) <
            within;
    final single = faces ? 40.0 : (photos ? 34.0 : 26.0);
    final groups = _groupsAt(camera, people, camera.zoom);
    return MarkerLayer(markers: [
      for (final group in groups)
        if (group.length == 1)
          Marker(
            key: Key('mapPerson-${group.single.profile.id}'),
            point: LatLng(group.single.latitude, group.single.longitude),
            width: single,
            height: single,
            child: GestureDetector(
              onTap: () => onOpen(group.single.profile),
              child: faces && group.single.profile.photoUrls.isNotEmpty
                  ? _FaceMarker(profile: group.single.profile, size: single)
                  : _MarkMarker(profile: group.single.profile, size: single),
            ),
          )
        else
          _cluster(group, photos: photos),
    ]);
  }

  /// Group markers' sizes, smallest to biggest (zoomed out, zoomed in).
  static const _smallGroup = 32.0;
  static const _bigGroup = 42.0;

  /// A group's marker: a circle with how many, bigger zoomed in (beside
  /// the marks) and for more people. Its key is its own (the first person
  /// in it), as no two markers may share one.
  Marker _cluster(List<MapPerson> group, {required bool photos}) {
    final center = LatLng(
      group.map((p) => p.latitude).reduce((a, b) => a + b) / group.length,
      group.map((p) => p.longitude).reduce((a, b) => a + b) / group.length,
    );
    final smallest = photos ? 32.0 : 24.0;
    final size = (smallest + 5 * math.log(group.length))
        .clamp(smallest, photos ? _bigGroup : _smallGroup)
        .toDouble();
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
              key: const Key('mapClusterCount'),
              style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: photos ? 13 : 12)),
        ),
      ),
    );
  }
}

/// [people] as they'd be grouped at [zoom] (the camera's or another):
/// whose markers would overlap on screen, as one group each:
/// anyone closer than a marker's width to a group joins it (and groups
/// that end up that close merge), so no two markers ever overlap.
List<List<MapPerson>> _groupsAt(
    MapCamera camera, List<MapPerson> people, double zoom) {
  // the biggest marker at this zoom, and a little room around it
  final apart = (zoom >= ExploreMap.photoZoom
          ? _PeopleLayer._bigGroup
          : _PeopleLayer._smallGroup) +
      8;
  final groups = <({List<MapPerson> people, Offset sum})>[];
  Offset center(({List<MapPerson> people, Offset sum}) g) =>
      g.sum / g.people.length.toDouble();
  for (final p in people) {
    final at = camera.projectAtZoom(LatLng(p.latitude, p.longitude), zoom);
    final near = groups.indexWhere((g) => (center(g) - at).distance < apart);
    if (near < 0) {
      groups.add((people: [p], sum: at));
    } else {
      final g = groups[near];
      groups[near] = (people: [...g.people, p], sum: g.sum + at);
    }
  }
  // a group's centre moves as people join: merge any now too close
  for (var merged = true; merged;) {
    merged = false;
    for (var i = 0; i < groups.length && !merged; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        if ((center(groups[i]) - center(groups[j])).distance < apart) {
          groups[i] = (
            people: [...groups[i].people, ...groups[j].people],
            sum: groups[i].sum + groups[j].sum
          );
          groups.removeAt(j);
          merged = true;
          break;
        }
      }
    }
  }
  return [for (final g in groups) g.people];
}

/// Someone on the map: HUNTR's mark in a dark circle (never their photo, so the map
/// loads none), ringed in the accent when they have a story I haven't
/// seen, with the online dot.
class _MarkMarker extends StatelessWidget {
  const _MarkMarker({required this.profile, required this.size});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final story = profile.hasStory && !profile.storySeen;
    final dot = math.max(9.0, size * 0.3);
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.22),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HuntrColors.surface,
            border: Border.all(
                color: story
                    ? HuntrColors.orange
                    : Colors.white.withValues(alpha: 0.85),
                width: story ? 2.5 : 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
          ),
          child: Image.asset('assets/huntr_mark.png',
              color: HuntrColors.orange, filterQuality: FilterQuality.medium),
        ),
        if (profile.online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HuntrColors.online,
                border: Border.all(color: HuntrColors.night, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Close in: their photo (with the online dot and a still story ring:
/// dozens of spinning ones would redraw the whole map every frame).
class _FaceMarker extends StatelessWidget {
  const _FaceMarker({required this.profile, required this.size});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: const Key('mapFace'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: profile.hasStory
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.85), width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
        child: Avatar(profile: profile, size: size, animateStory: false),
      );
}

/// Where I am (only my own, exact position, to me): a dot in the accent
/// with a soft ring pulsing out of it (still when the device asks for
/// less motion).
class _MyDot extends StatefulWidget {
  const _MyDot();

  @override
  State<_MyDot> createState() => _MyDotState();
}

class _MyDotState extends State<_MyDot> with SingleTickerProviderStateMixin {
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

/// Where the map meets the header (top) or the tabs (bottom): a short
/// fade from the app's night, so the map has no hard edge.
class _Fade extends StatelessWidget {
  const _Fade({required this.fromTop});

  final bool fromTop;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          height: fromTop ? 28 : 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                HuntrColors.night.withValues(alpha: 0.9),
                HuntrColors.night.withValues(alpha: 0),
              ],
            ),
          ),
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

/// Zoom in, how wide the map shown is, zoom out: one card.
class _ZoomCard extends StatelessWidget {
  const _ZoomCard(
      {required this.across, required this.onZoomIn, required this.onZoomOut});

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
      decoration: _floating(radius: 23),
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

/// Things floating over the map: the app's surface, a hairline edge and a
/// soft shadow.
BoxDecoration _floating({required double radius}) => BoxDecoration(
      color: HuntrColors.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: HuntrColors.border),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
      ],
    );

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
  Widget build(BuildContext context) => DecoratedBox(
        decoration: _floating(radius: 23),
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

/// A light map made dark ([night]): its brightness turned around (light
/// ground goes near black, dark names go bright) and coloured from the
/// app's night towards its accent, so it wears the chosen theme.
Widget _nightIf(bool night, Widget map) {
  if (!night) return map;
  final accent = HuntrColors.orange;
  final ground = HuntrColors.night;
  // per channel: the ground, plus (how dark it was) x (a little grey and
  // half the accent)
  List<double> row(double accentChannel, double groundChannel) {
    final reach = 0.35 * 255 + 0.45 * accentChannel * 255;
    return [
      -reach * 0.2126 / 255,
      -reach * 0.7152 / 255,
      -reach * 0.0722 / 255,
      0,
      groundChannel * 255 + reach,
    ];
  }

  return ColorFiltered(
    colorFilter: ColorFilter.matrix([
      ...row(accent.r, ground.r),
      ...row(accent.g, ground.g),
      ...row(accent.b, ground.b),
      0,
      0,
      0,
      1,
      0,
    ]),
    child: map,
  );
}
