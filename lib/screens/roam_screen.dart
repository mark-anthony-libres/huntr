import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart' show SessionRejectedException;
import '../services/place_search.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/huntr_tile_layer.dart';
import '../widgets/roam/roaming.dart';

/// Makes the place search Roam uses (tests put a fake one here).
PlaceSearch Function() newPlaceSearch = PlaceSearch.new;

/// How many places Recent keeps.
const _recentKept = 5;

/// Roam: pick anywhere to look around - search a place (a list of matches
/// as you type, and the places roamed last), or move the map under the pin
/// - then Roam here. While roaming, Back to my location ends it. Pops with
/// true when roaming changed.
class RoamScreen extends StatefulWidget {
  const RoamScreen({super.key});

  @override
  State<RoamScreen> createState() => _RoamScreenState();
}

class _RoamScreenState extends State<RoamScreen> {
  final _map = MapController();
  final _query = TextEditingController();
  final _focus = FocusNode();
  late final PlaceSearch _places = newPlaceSearch();

  Timer? _typing;
  Timer? _settling;
  List<Place> _results = const [];
  List<Place> _recent = const [];
  bool _searching = false;
  String? _searchProblem;

  /// The place to roam: picked from the list, or named where the map
  /// stopped (null: still finding out).
  Place? _picked;
  bool _naming = false;
  bool _saving = false;

  /// Which search is the latest (an older answer is dropped).
  int _searchNumber = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _query.addListener(_typed);
    unawaited(_loadRecent());
  }

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
    _typing?.cancel();
    _settling?.cancel();
    _query.dispose();
    _focus.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = AppScope.read(context).devicePreferences;
    if (prefs == null) return;
    try {
      final saved = await prefs.readRecentRoams();
      if (!mounted) return;
      setState(() => _recent = [
            for (final json in saved)
              if (Place.fromJson(json) case final place?) place
          ]);
    } catch (error) {
      debugPrint('Recent roams not loaded: $error');
    }
  }

  void _remember(Place place) {
    final prefs = AppScope.read(context).devicePreferences;
    final kept = [
      place,
      for (final p in _recent)
        if (p.name != place.name || p.detail != place.detail) p
    ].take(_recentKept).toList();
    _recent = kept;
    unawaited(prefs
        ?.saveRecentRoams([for (final p in kept) p.toJson()]).catchError(
            (Object error) => debugPrint('Recent roams not saved: $error')));
  }

  /// Searches a moment after typing stops.
  void _typed() {
    _typing?.cancel();
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchProblem = null;
      });
      return;
    }
    _typing = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!_places.available) {
      setState(() => _searchProblem =
          'Search isn\'t available. Move the map to choose a spot.');
      return;
    }
    final number = ++_searchNumber;
    setState(() {
      _searching = true;
      _searchProblem = null;
    });
    try {
      final found = await _places.search(q);
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _results = found;
        _searching = false;
        _searchProblem = found.isEmpty ? 'No places found.' : null;
      });
    } catch (error) {
      debugPrint('Place search failed: $error');
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _searching = false;
        _searchProblem = 'Search didn\'t work. Please try again.';
      });
    }
  }

  /// A place from the list (or Recent): the map goes there.
  void _choose(Place place) {
    _focus.unfocus();
    _settling?.cancel();
    setState(() {
      _picked = place;
      _naming = false;
      _results = const [];
    });
    _query.removeListener(_typed);
    _query.clear();
    _query.addListener(_typed);
    _map.move(LatLng(place.latitude, place.longitude), 13);
  }

  /// The map was moved by hand: the spot under the pin is named once it
  /// settles.
  void _mapEvent(MapEvent event) {
    if (event is! MapEventMoveEnd && event is! MapEventFlingAnimationEnd) {
      return;
    }
    if (event.source == MapEventSource.mapController) return;
    _settling?.cancel();
    setState(() {
      _picked = null;
      _naming = true;
    });
    _settling = Timer(const Duration(milliseconds: 450), _nameTheSpot);
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
      _remember(place);
      if (mounted) Navigator.pop(context, true);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('Roaming failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't roam there. Please try again.")));
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
    final me = app.myLocation;
    final start = roam != null
        ? LatLng(roam.latitude, roam.longitude)
        : me != null
            ? LatLng(me.latitude, me.longitude)
            : const LatLng(20, 0);
    final typing = _focus.hasFocus;
    final showList = typing && _query.text.trim().length >= 2;
    final showRecent = typing && !showList && _recent.isNotEmpty;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: HuntrColors.night,
      resizeToAvoidBottomInset: false,
      // the map, and below it (not over it: its credits stay in view) the
      // place card
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              key: const Key('roamMap'),
              mapController: _map,
              options: MapOptions(
                initialCenter: start,
                initialZoom: roam != null || me != null ? 12 : 2,
                minZoom: 2,
                maxZoom: 17,
                backgroundColor: HuntrColors.night,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapEvent: _mapEvent,
                onTap: (_, __) => _focus.unfocus(),
              ),
              children: const [
                HuntrTileLayer(creditsAt: AttributionAlignment.bottomRight),
              ],
            ),

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

            // search, and what it found
            Positioned(
              left: 12,
              right: 12,
              top: top + 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
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
                    Expanded(
                      child: TextField(
                        key: const Key('roamSearch'),
                        controller: _query,
                        focusNode: _focus,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          if (_results.isNotEmpty) _choose(_results.first);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search a city or area',
                          filled: true,
                          fillColor: HuntrColors.surface,
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: _query.clear,
                                ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                const BorderSide(color: HuntrColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                const BorderSide(color: HuntrColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: HuntrColors.orange, width: 1.4),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  if (showList || showRecent) const SizedBox(height: 8),
                  if (showList)
                    _Card(
                      child: _searching && _results.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                  child: SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5))),
                            )
                          : _searchProblem != null && _results.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(_searchProblem!,
                                      key: const Key('roamSearchProblem'),
                                      style: const TextStyle(
                                          color: HuntrColors.muted)),
                                )
                              : Column(children: [
                                  for (final (i, place) in _results.indexed)
                                    _PlaceRow(
                                      key: Key('roamResult-$i'),
                                      place: place,
                                      onTap: () => _choose(place),
                                    ),
                                ]),
                    ),
                  if (showRecent)
                    _Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('RECENT',
                                style: TextStyle(
                                    color: HuntrColors.muted,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final place in _recent)
                                ActionChip(
                                  avatar: const Icon(Icons.history_rounded,
                                      size: 16),
                                  label: Text(place.name),
                                  onPressed: () => _choose(place),
                                ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),

        // the place, and Roam here
        if (!typing)
          _PlaceCard(
            place: _picked,
            naming: _naming,
            me: me,
            saving: _saving,
            roaming: roam != null,
            onRoam: _roamHere,
            onHome: _goHome,
          ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: HuntrColors.surface,
        elevation: 8,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({super.key, required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: HuntrColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.place_outlined,
                  size: 19, color: HuntrColors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (place.detail != null)
                    Text(place.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: HuntrColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ]),
        ),
      );
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
