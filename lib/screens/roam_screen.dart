import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart'
    show BackendException, SessionRejectedException;
import '../services/place_search.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/huntr_map.dart';
import '../widgets/map_controls.dart'
    show MapButton, MapInfoPoint, MapNote, MyLocationDot, reachBounds;
import '../widgets/roam/roaming.dart';

/// How far from where I am I can roam (km) until the backend says
/// (ROAM_REACH_KM).
const defaultRoamReachKm = 20.0;

/// Makes the place naming Roam uses (tests put a fake one here).
PlaceSearch Function() newPlaceSearch = PlaceSearch.new;

/// Roam: look around somewhere near - within the roam reach (20 km) around
/// where I am, drawn as a circle. Move the map under
/// the pin (let go outside the circle: back to its edge), then Roam here.
/// While roaming, Stop roaming ends it. Pops with true when roaming
/// changed.
class RoamScreen extends StatefulWidget {
  const RoamScreen({super.key});

  @override
  State<RoamScreen> createState() => _RoamScreenState();
}

class _RoamScreenState extends State<RoamScreen> {
  final _map = MapController();
  late final PlaceSearch _places = newPlaceSearch();
  Timer? _settling;

  /// The place to roam: named where the map stopped (null: still finding
  /// out).
  Place? _picked;
  bool _naming = false;
  bool _saving = false;

  /// The map is being moved by hand (the pin lifts).
  bool _moving = false;

  /// Which naming is the latest (an older answer is dropped).
  int _nameAsked = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final roam = AppScope.read(context).myRoam;
    if (_picked == null && roam != null) {
      _picked = Place(
          name: roam.place,
          detail: roam.detail,
          latitude: roam.latitude,
          longitude: roam.longitude);
    }
  }

  @override
  void dispose() {
    _settling?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Where I am (the circle's middle); null when not known.
  LatLng? get _me {
    final mine = AppScope.read(context).myLocation;
    return mine == null ? null : LatLng(mine.latitude, mine.longitude);
  }

  /// How far from where I am I can roam (the backend's, else 20 km).
  double get _reachKm =>
      AppScope.read(context).roamReachKm ?? defaultRoamReachKm;

  /// The map was moved by hand: let go outside the circle, the pin goes
  /// back to its edge; then the spot under it is named once it settles.
  void _mapEvent(MapEvent event) {
    if (event.source == MapEventSource.mapController) return;
    if (event is MapEventMoveStart && !_moving) {
      setState(() => _moving = true);
      return;
    }
    if (event is! MapEventMoveEnd && event is! MapEventFlingAnimationEnd) {
      return;
    }
    _moving = false;
    _keepInCircle();
    _settling?.cancel();
    setState(() {
      _picked = null;
      _naming = true;
    });
    _settling = Timer(const Duration(milliseconds: 450), _nameTheSpot);
  }

  /// The pin back inside the circle (to the nearest point of its edge).
  void _keepInCircle() {
    final me = _me;
    if (me == null) return;
    final camera = _map.camera;
    const distance = Distance();
    final metres = distance.as(LengthUnit.Meter, me, camera.center);
    final reach = _reachKm * 1000;
    if (metres <= reach) return;
    final edge =
        distance.offset(me, reach, distance.bearing(me, camera.center));
    _map.move(edge, camera.zoom);
  }

  Future<void> _nameTheSpot() async {
    final center = _map.camera.center;
    final asked = ++_nameAsked;
    Place? named;
    try {
      named = await _places.at(center.latitude, center.longitude);
    } catch (error) {
      debugPrint('Naming the spot failed: $error');
    }
    // moved again meanwhile: the newer one's answer counts
    if (!mounted || asked != _nameAsked) return;
    setState(() {
      _naming = false;
      _picked = named ??
          Place(
              name: 'This spot',
              detail:
                  '${center.latitude.toStringAsFixed(3)}, ${center.longitude.toStringAsFixed(3)}',
              latitude: center.latitude,
              longitude: center.longitude);
    });
  }

  Future<void> _roamHere() async {
    final place = _picked;
    final explore = ServicesScope.exploreOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (place == null || explore == null || token == null || _saving) return;
    setState(() => _saving = true);
    try {
      final roam = await explore.startRoam(token,
          latitude: place.latitude,
          longitude: place.longitude,
          place: place.name,
          detail: place.detail);
      app.setMyRoam(roam);
      if (mounted) Navigator.pop(context, true);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('Roaming failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is BackendException
              ? error.message
              : "Couldn't roam there. Please try again.")));
    }
  }

  Future<void> _goHome() async {
    final explore = ServicesScope.exploreOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (explore == null || token == null || _saving) return;
    setState(() => _saving = true);
    try {
      await explore.stopRoam(token);
      app.setMyRoam(null);
      if (mounted) Navigator.pop(context, true);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('Stopping roam failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't go back. Please try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final roam = app.myRoam;
    final me = _me;
    final reachKm = _reachKm;
    final start = roam != null
        ? LatLng(roam.latitude, roam.longitude)
        : me ?? const LatLng(20, 0);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: HuntrColors.night,
      // the map, and below it (not over it: its credits stay in view) the
      // place card
      body: Column(children: [
        Expanded(
          child: HuntrMap(
            key: const Key('roamMap'),
            controller: _map,
            center: start,
            zoom: 11,
            // opens on the whole circle (out far enough to see all of it)
            minZoom: 7,
            fit: me == null
                ? null
                : CameraFit.bounds(
                    bounds: reachBounds(me, reachKm),
                    padding: const EdgeInsets.fromLTRB(16, 80, 16, 16)),
            // not far past the circle while dragging (the pin comes back
            // inside it when let go)
            cameraConstraint: me == null
                ? null
                : CameraConstraint.containCenter(
                    bounds: reachBounds(me, reachKm)),
            onEvent: _mapEvent,
            // the spot under the pin named at once (not only once moved)
            onReady: (_) {
              if (_picked != null) return;
              setState(() => _naming = true);
              unawaited(_nameTheSpot());
            },
            layers: [
              if (me != null) ...[
                // where I can roam: the reach around where I am
                // outside it, the map greyed and blurred
                _OutsideCircle(
                    key: const Key('roamOutside'),
                    center: me,
                    metres: reachKm * 1000),
                CircleLayer(circles: [
                  CircleMarker(
                    key: const Key('roamCircle'),
                    point: me,
                    radius: reachKm * 1000,
                    useRadiusInMeter: true,
                    color: Colors.transparent,
                    borderColor: HuntrColors.orange.withValues(alpha: 0.7),
                    borderStrokeWidth: 2,
                  ),
                ]),
                // and where I am
                MarkerLayer(markers: [
                  Marker(
                    point: me,
                    width: 64,
                    height: 64,
                    child: const MyLocationDot(),
                  ),
                ]),
              ],
            ],
            buttons: [
              if (me != null)
                MapButton(
                  key: const Key('roamMe'),
                  tooltip: 'Where I am',
                  icon: Icons.my_location_rounded,
                  onPressed: () => _map.move(me, _map.camera.zoom),
                ),
            ],
            overlays: [
              // the pin: where Roam here roams (the middle of the map); it
              // lifts while the map moves, its shadow on the spot
              IgnorePointer(child: _Pin(lifted: _moving)),
              // back, and what the circle is
              Positioned(
                left: 12,
                right: 12,
                top: top + 12,
                child: Row(children: [
                  IconButton.filled(
                    tooltip: 'Back',
                    style: IconButton.styleFrom(
                      backgroundColor: HuntrColors.surface,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                      side: const BorderSide(color: HuntrColors.border),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  // as on Explore's map: tapped, how Roam works
                  Flexible(
                    child: MapNote(
                      key: const Key('roamReachNote'),
                      icon: roamIcon,
                      text: me == null
                          ? 'Share your location to roam around it'
                          : 'Roam up to ${reachKm.round()} km from you',
                      onTap: () => showRoamInfo(context, reachKm),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),

        // the place, and Roam here
        _PlaceCard(
          place: _picked,
          naming: _naming,
          me: app.myLocation,
          saving: _saving,
          roaming: roam != null,
          onRoam: _roamHere,
          onHome: _goHome,
        ),
      ]),
    );
  }
}

/// The bottom card: the place under the pin (how far from me), what roaming
/// means, Roam here; and while roaming, Stop roaming.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.naming,
    required this.me,
    required this.saving,
    required this.roaming,
    required this.onRoam,
    required this.onHome,
  });

  final Place? place;
  final bool naming;
  final GeoPoint? me;
  final bool saving;
  final bool roaming;
  final VoidCallback onRoam;
  final VoidCallback onHome;

  String? get _far {
    final p = place, mine = me;
    if (p == null || mine == null) return null;
    final km = const Distance().as(LengthUnit.Kilometer,
        LatLng(mine.latitude, mine.longitude), LatLng(p.latitude, p.longitude));
    if (km < 1) return 'Near you';
    final whole = km
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '$whole km from you';
  }

  @override
  Widget build(BuildContext context) {
    final p = place;
    final far = _far;
    final ready = p != null && !naming && !saving;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: HuntrColors.border)),
        boxShadow: [
          BoxShadow(
              color: Colors.black54, blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      // wide screens: a comfortable width, in the middle
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: HuntrColors.accentGradient,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(roamIcon, color: Colors.black),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    // from the left (it centres by default)
                    layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, if (current != null) current]),
                    child: naming || p == null
                        ? Row(
                            key: const ValueKey('finding'),
                            children: [
                              if (naming) ...[
                                const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Text(
                                    naming
                                        ? 'Finding the place…'
                                        : 'Move the map to choose a spot',
                                    key: const Key('roamPlaceName'),
                                    style: const TextStyle(
                                        color: HuntrColors.muted,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          )
                        : Column(
                            key: ValueKey('${p.name}|${p.detail}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ROAM TO',
                                  style: TextStyle(
                                      color: HuntrColors.muted,
                                      fontSize: 11,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(p.name,
                                  key: const Key('roamPlaceName'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800)),
                              if (p.detail != null)
                                Text(p.detail!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: HuntrColors.muted,
                                        fontSize: 13.5)),
                            ],
                          ),
                  ),
                ),
                // how far from me
                if (far != null && p != null && !naming) ...[
                  const SizedBox(width: 10),
                  Container(
                    key: const Key('roamDistance'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: HuntrColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(far,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              const SizedBox(height: 16),
              Row(children: [
                // roaming: Stop roaming, beside Roam here
                if (roaming) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('roamHome'),
                      onPressed: saving ? null : onHome,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(color: HuntrColors.border),
                      ),
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Stop roaming'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('roamHere'),
                    onPressed: ready ? onRoam : null,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black))
                        : const Icon(roamIcon, size: 18),
                    label: const Text('Roam here'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pin in the middle of the map: up a little while the map moves (its
/// shadow stays on the spot, smaller), down on it when it stops.
class _Pin extends StatelessWidget {
  const _Pin({required this.lifted});

  final bool lifted;

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 60,
          height: 120,
          child: Stack(alignment: Alignment.center, children: [
            // the shadow, on the spot (the middle)
            AnimatedContainer(
              duration: _duration,
              width: lifted ? 10 : 16,
              height: lifted ? 4 : 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: lifted ? 0.35 : 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // the pin, its point on the spot (higher while lifted)
            AnimatedPositioned(
              duration: _duration,
              curve: Curves.easeOutBack,
              bottom: lifted ? 72 : 58,
              child: Icon(Icons.location_on_rounded,
                  key: const Key('roamPin'),
                  size: 50,
                  color: HuntrColors.ember,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 8),
                  ]),
            ),
          ]),
        ),
      );
}

/// The map outside the circle greyed and blurred (inside it, as it is): a
/// layer, over the map's images.
class _OutsideCircle extends StatelessWidget {
  const _OutsideCircle({super.key, required this.center, required this.metres});

  final LatLng center;
  final double metres;

  /// Grey: each colour to its brightness.
  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final middle = camera.latLngToScreenOffset(center);
    final east = camera
        .latLngToScreenOffset(const Distance().offset(center, metres, 90));
    final radius = (east - middle).distance;
    return IgnorePointer(
      child: ClipPath(
        clipper: _Outside(middle, radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(
              outer: _grey, inner: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4)),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
        ),
      ),
    );
  }
}

/// Everything but the circle.
class _Outside extends CustomClipper<ui.Path> {
  _Outside(this.middle, this.radius);

  final Offset middle;
  final double radius;

  @override
  ui.Path getClip(Size size) => ui.Path.combine(
      // the shape itself (the even-odd rule isn't kept by every renderer:
      // on the web the blur went inside the circle instead)
      ui.PathOperation.difference,
      ui.Path()..addRect(Offset.zero & size),
      ui.Path()..addOval(Rect.fromCircle(center: middle, radius: radius)));

  @override
  bool shouldReclip(_Outside old) =>
      old.middle != middle || old.radius != radius;
}

/// The note's info: how Roam works.
Future<void> showRoamInfo(BuildContext context, double reachKm) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('roamInfo'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How Roam works',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              MapInfoPoint(
                icon: Icons.radio_button_unchecked_rounded,
                title: 'Up to ${reachKm.round()} km from you',
                text: 'Roam anywhere inside the circle around where you '
                    'are. Move the map to put the pin where you want to look '
                    'around, then tap Roam here.',
              ),
              const MapInfoPoint(
                icon: roamIcon,
                title: 'Seen there as roaming',
                text: 'While you roam, Explore shows the people around that '
                    'spot. They see you there with a Roaming label, never '
                    'with a distance.',
              ),
              const MapInfoPoint(
                icon: Icons.lock_outline_rounded,
                title: 'Your real location stays private',
                text: "The spot you roam isn't where you are. A location you "
                    'share in chat is always your real one.',
              ),
              const MapInfoPoint(
                icon: Icons.my_location_rounded,
                title: 'Stop any time',
                text: 'Tap Stop roaming to be back where you are.',
              ),
            ],
          ),
        ),
      ),
    );
