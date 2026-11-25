import 'dart:async';

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
    show MapButton, defaultMapReachKm, reachBounds;
import '../widgets/roam/roaming.dart';

/// Makes the place naming Roam uses (tests put a fake one here).
PlaceSearch Function() newPlaceSearch = PlaceSearch.new;

/// Roam: look around somewhere near - within the reach (as far as Explore's
/// map goes, 50 km) around where I am, drawn as a circle. Move the map under
/// the pin (let go outside the circle: back to its edge), then Roam here.
/// While roaming, Back to my location ends it. Pops with true when roaming
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

  double get _reachKm => AppScope.read(context).mapReachKm ?? defaultMapReachKm;

  /// The map was moved by hand: let go outside the circle, the pin goes
  /// back to its edge; then the spot under it is named once it settles.
  void _mapEvent(MapEvent event) {
    if (event is! MapEventMoveEnd && event is! MapEventFlingAnimationEnd) {
      return;
    }
    if (event.source == MapEventSource.mapController) return;
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
    Place? named;
    try {
      named = await _places.at(center.latitude, center.longitude);
    } catch (error) {
      debugPrint('Naming the spot failed: $error');
    }
    if (!mounted) return;
    final now = _map.camera.center;
    // moved again meanwhile: that one's named instead
    if ((now.latitude - center.latitude).abs() > 1e-6 ||
        (now.longitude - center.longitude).abs() > 1e-6) {
      return;
    }
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
            layers: [
              if (me != null) ...[
                // where I can roam: the reach around where I am
                CircleLayer(circles: [
                  CircleMarker(
                    key: const Key('roamCircle'),
                    point: me,
                    radius: reachKm * 1000,
                    useRadiusInMeter: true,
                    color: HuntrColors.orange.withValues(alpha: 0.06),
                    borderColor: HuntrColors.orange.withValues(alpha: 0.7),
                    borderStrokeWidth: 2,
                  ),
                ]),
                // and where I am
                MarkerLayer(markers: [
                  Marker(
                    point: me,
                    width: 18,
                    height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HuntrColors.active,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
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
              // the pin: where Roam here roams (the middle of the map)
              IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: Padding(
                    // its point, not its middle, on the spot
                    padding: const EdgeInsets.only(bottom: 46),
                    child: Icon(Icons.location_on_rounded,
                        key: const Key('roamPin'),
                        size: 48,
                        color: HuntrColors.ember),
                  ),
                ),
              ),
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
                  Flexible(
                    child: Container(
                      key: const Key('roamReachNote'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: HuntrColors.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: HuntrColors.border),
                      ),
                      child: Text(
                          me == null
                              ? 'Share your location to roam around it.'
                              : 'Roam anywhere in the circle: up to '
                                  '${reachKm.round()} km from you.',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
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
/// means, Roam here; and while roaming, Back to my location.
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
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: HuntrColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: HuntrColors.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(roamIcon, color: HuntrColors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: naming || p == null
                  ? Text(
                      naming
                          ? 'Finding the place…'
                          : 'Move the map to choose a spot',
                      key: const Key('roamPlaceName'),
                      style: const TextStyle(
                          color: HuntrColors.muted,
                          fontSize: 15,
                          fontWeight: FontWeight.w600))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            key: const Key('roamPlaceName'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                        Text(
                            [
                              if (p.detail != null) p.detail!,
                              if (far != null) far
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: HuntrColors.muted, fontSize: 13.5)),
                      ],
                    ),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HuntrColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 18, color: HuntrColors.muted),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'People there see you as roaming. A location you share '
                      'in chat is always your real one.',
                      style: TextStyle(color: HuntrColors.muted, height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('roamHere'),
            onPressed: p == null || naming || saving ? null : onRoam,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.black))
                : const Text('Roam here'),
          ),
          if (roaming) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('roamHome'),
              onPressed: saving ? null : onHome,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Back to my location'),
            ),
          ],
        ],
      ),
    );
  }
}
