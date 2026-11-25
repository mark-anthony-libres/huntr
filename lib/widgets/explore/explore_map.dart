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
import '../roam/roaming.dart';
import '../avatar.dart';
import '../huntr_map.dart';
import '../map_controls.dart';

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
///
/// MAP_FALLBACK_URL (+ MAP_FALLBACK_ATTRIBUTION, and MAP_FALLBACK_MAX_ZOOM:
/// the closest zoom it has images for, e.g. 18 for CARTO): another provider, used
/// when the first one's images keep failing (e.g. its monthly quota is used
/// up). Without one, or when it fails too, the map says it can't be shown
/// (people are still on it, and in the list).
class MapTiles {
  const MapTiles(
      {required this.url,
      required this.attributions,
      this.night = false,
      this.maxNativeZoom = ExploreMap.tileMaxZoom,
      this.fallback});

  /// '' for no map images (e.g. tests).
  final String url;
  final List<String> attributions;

  /// A light, colourful map made dark like the app: near black, with
  /// streets' names and water in the accent.
  final bool night;

  /// The closest zoom this provider has images for; closer in, those are
  /// enlarged (never asked for: a provider refuses zooms it doesn't have,
  /// and that would count as failing).
  final int maxNativeZoom;

  /// Where the images come from when these keep failing.
  final MapTiles? fallback;

  /// These, then each fallback in turn.
  List<MapTiles> get inOrder => [this, ...?fallback?.inOrder];

  static const _mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

  /// MapTiler's key (empty: none), for its place search too (Roam).
  static String get mapTilerKey => _mapTilerKey;
  static const _customUrl = String.fromEnvironment('MAP_TILE_URL');
  static const _customCredit = String.fromEnvironment('MAP_TILE_ATTRIBUTION');
  static const _fallbackUrl = String.fromEnvironment('MAP_FALLBACK_URL');
  static const _fallbackCredit =
      String.fromEnvironment('MAP_FALLBACK_ATTRIBUTION');
  static const _fallbackMaxZoom = int.fromEnvironment('MAP_FALLBACK_MAX_ZOOM',
      defaultValue: ExploreMap.tileMaxZoom);

  static MapTiles? get _configuredFallback => _fallbackUrl.isEmpty
      ? null
      : MapTiles(
          url: _fallbackUrl,
          attributions: [
            if (_fallbackCredit.isNotEmpty) _fallbackCredit,
            'OpenStreetMap contributors',
          ],
          maxNativeZoom: _fallbackMaxZoom);

  static MapTiles get configured {
    if (_customUrl.isNotEmpty) {
      return MapTiles(
          url: _customUrl,
          attributions: [
            if (_customCredit.isNotEmpty) _customCredit,
            'OpenStreetMap contributors',
          ],
          fallback: _configuredFallback);
    }
    if (_mapTilerKey.isNotEmpty) {
      return MapTiles(
          url: 'https://api.maptiler.com/maps/dataviz-dark/{z}/{x}/{y}{r}.png'
              '?key=$_mapTilerKey',
          attributions: const ['MapTiler', 'OpenStreetMap contributors'],
          fallback: _configuredFallback);
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

  /// Where the map is around: where I roam, else where I am.
  LatLng? get _me {
    final app = AppScope.read(context);
    final roam = app.myRoam;
    if (roam != null) return LatLng(roam.latitude, roam.longitude);
    final mine = app.myLocation;
    return mine == null ? null : LatLng(mine.latitude, mine.longitude);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Once the map stops moving: the people in what's on screen.
  void _moved(MapCamera camera) {
    _settle?.cancel();
    if (_covered(camera)) return; // the last answer already has it
    _settle = Timer(const Duration(milliseconds: 400), _load);
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
        // so their profile opens from here (they may not be in the list)
        app.rememberPeople([for (final p in found.people) p.profile]);
        _more = found.more;
        _reachKm = found.reachKm ?? _reachKm;
        // (Roam's map keeps to the same)
        app.mapReachKm = _reachKm ?? app.mapReachKm;
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

  /// None of the map's image sources works (the map says so).
  bool _noMap = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // the list's filters and chips apply here too
    final shown = [
      for (final p in _people)
        if (app.showsInExplore(p.profile)) p
    ];
    final me = _me;
    // none of the map's sources works: the map says so (people are still on it)
    final noMap = _noMap;
    return HuntrMap(
      key: const Key('exploreMap'),
      controller: _map,
      center: me ?? _fallback,
      // all of what's shown stays within the backend's reach of me: no
      // panning past it, and no zooming out wider than it (the backend cuts
      // any area asked for to it, too)
      cameraConstraint: switch ((me, _reachKm)) {
        (final me?, final km?) =>
          CameraConstraint.contain(bounds: reachBounds(me, km)),
        _ => const CameraConstraint.unconstrained(),
      },
      tiles: widget.tiles,
      onUnavailable: () => setState(() => _noMap = true),
      onReady: (_) => _load(),
      onMoved: _moved,
      controlsBottom: widget.controlsBottom,
      buttons: [
        if (me != null)
          MapButton(
            key: const Key('mapMe'),
            tooltip: 'Around me',
            icon: Icons.my_location_rounded,
            onPressed: () => _map.move(me, ExploreMap.photoZoom),
          ),
      ],
      layers: [
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
      ],
      overlays: [
        // ---- soft edges: the map fades into the header and the tabs ----
        const Positioned(
            left: 0, right: 0, top: 0, child: _Fade(fromTop: true)),
        const Positioned(
            left: 0, right: 0, bottom: 0, child: _Fade(fromTop: false)),

        // ---- loading, and what the map shows ----
        if (_loading)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
                minHeight: 2, color: HuntrColors.orange),
          ),
        Positioned(
          left: 12,
          right: 76,
          top: 10,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _Note(
              key: const Key('mapNote'),
              // the usual note: tap to learn how locations are shown
              onTap: _error == null && !noMap
                  ? () => showMapLocationsInfo(context)
                  : null,
              icon: _error != null
                  ? Icons.wifi_off_rounded
                  : noMap
                      ? Icons.map_outlined
                      : Icons.blur_on_rounded,
              text: _error ??
                  (noMap
                      ? "The map can't be shown right now. People are still on "
                          'it, or use the list.'
                      : _more
                          ? 'Showing the nearest ${shown.length}. Zoom in for more.'
                          : 'Locations are approximate'),
              error: _error != null || noMap,
            ),
          ),
        ),
      ],
    );
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
              child: Stack(clipBehavior: Clip.none, children: [
                faces && group.single.profile.photoUrls.isNotEmpty
                    ? _FaceMarker(profile: group.single.profile, size: single)
                    : _MarkMarker(profile: group.single.profile, size: single),
                // roaming: here to look around, not here
                if (group.single.profile.roaming != null)
                  Positioned(
                    top: single + 2,
                    left: -40,
                    right: -40,
                    child: const Center(
                        child: IgnorePointer(child: RoamingTag(small: true))),
                  ),
              ]),
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

/// "Locations are approximate", tapped: how the map shows people.
Future<void> showMapLocationsInfo(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _MapLocationsInfo(),
    );

class _MapLocationsInfo extends StatelessWidget {
  const _MapLocationsInfo();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('mapLocationsInfo'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How your location works on the map',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              const _InfoPoint(
                icon: Icons.blur_on_rounded,
                title: 'Your exact location stays private',
                text: 'To protect your privacy, we show you at an approximate '
                    'spot within an area about 500 m across, not your exact '
                    'location. Your spot stays the same until you move to '
                    'another area, so nobody can use the map to find your '
                    'home or street.',
              ),
              const _InfoPoint(
                icon: Icons.people_alt_outlined,
                title: 'Distance is only an estimate',
                text: 'People nearby may appear closer or farther away than '
                    'they really are. The distance shown on profiles is a '
                    'helpful guide, not an exact measurement.',
              ),
              const _InfoPoint(
                icon: Icons.workspaces_outline,
                title: 'Find people around you',
                text: "When zoomed out, nearby people may appear together as "
                    "a number. Tap the number to see who's there. Zoom in to "
                    'see their photos. Your own location appears as a '
                    'glowing dot that only you can see.',
              ),
              const _InfoPoint(
                icon: Icons.visibility_off_outlined,
                title: "You're in control of who sees you",
                text: 'Only people who share their distance and have Show me '
                    'on the map enabled will appear on the map.\n\nWant to '
                    'hide yourself? Go to Settings → Privacy and turn off '
                    "Show me on the map. You'll still be visible in the "
                    'Explore list.',
              ),
            ],
          ),
        ),
      );
}

class _InfoPoint extends StatelessWidget {
  const _InfoPoint(
      {required this.icon, required this.title, required this.text});

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
