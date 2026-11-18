import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../services/huntr_backend.dart';
import '../services/services_scope.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pill_chip.dart';
import '../widgets/install_banner.dart';
import '../widgets/profile_tile.dart';
import '../widgets/stories/story_tray.dart';
import 'profile_pager.dart';
import '../widgets/explore/empty_explore.dart';
import '../widgets/explore/explore_map.dart';
import '../widgets/explore/filter_sheet.dart';
import '../widgets/explore/looking_for_dropdown.dart';
import '../widgets/me/section_states.dart';
import '../widgets/new_items_pill.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  // ---- people nearby, from the backend ----
  bool _started = false;
  bool _loading = false;
  String? _loadError;

  final _scroll = ScrollController();

  /// The list's header (the title): the pill sits under it at the top.
  final _listHeader = GlobalKey();

  /// Its height, measured once it's laid out (not during a build).
  double _headerHeight = 0;

  void _measureHeader() {
    final box = _listHeader.currentContext?.findRenderObject();
    if (!mounted || box is! RenderBox || !box.hasSize) return;
    if (box.size.height != _headerHeight) {
      setState(() => _headerHeight = box.size.height);
    }
  }

  /// Where the pill sits: under the header while it shows, then at the top
  /// as the list scrolls (like X's under its own bar).
  double get _pillTop {
    final scrolled = _scroll.hasClients ? _scroll.offset : 0.0;
    return (_headerHeight - scrolled).clamp(8.0, double.infinity);
  }

  /// People who arrived nearby, or came online, since the list loaded (the
  /// pill at the top; tapped, the list starts over with them).
  List<Profile> _arrived = const [];

  /// Of [_arrived], someone not in the list at all (otherwise they only
  /// came online).
  bool _someoneNew = false;
  late final _watch = NewItemsWatch(
      context: context, every: _arrivedEvery, check: _checkArrived);
  static const _arrivedEvery = Duration(seconds: 60);

  /// Explore as a map instead of the list.
  bool _mapView = false;

  /// The order the list was loaded in; another one (Filters) loads it again.
  /// The filters (and order) the list was loaded with, as the backend gets
  /// them: when they change, the list loads again from the top.
  String? _loadedFilters;

  /// The list loading again after the filters changed (once, after this
  /// build).
  Timer? _reload;

  static String _filtersKey(ExploreFilters f) =>
      Uri(queryParameters: f.backendQuery).query;

  /// A fresh first page of Explore: the stories tray starts over too.
  int _trayGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || ServicesScope.exploreOf(context) == null) return;
    _started = true;
    _loadNearby();
    _watch.start();
  }

  /// The first page (or, with [more], the next one).
  Future<void> _loadNearby({bool more = false}) async {
    final explore = ServicesScope.exploreOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final offset = more ? app.nearbyNextOffset : 0;
    if (explore == null || token == null || offset == null || _loading) return;
    final filters = app.filters;
    final key = _filtersKey(filters);
    _loadedFilters = key;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page =
          await explore.fetchNearby(token, offset: offset, filters: filters);
      // the filters changed while this page was on its way: it's not wanted
      if (key != _filtersKey(app.filters)) return;
      app.setNearby(page.people, nextOffset: page.nextOffset, append: more);
      if (!more && mounted) {
        setState(() {
          _trayGeneration++;
          // a fresh first page: nobody waits any more
          _arrived = const [];
          _someoneNew = false;
        });
      }
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      // the filters changed while loading: now the list with the new ones
      if (mounted && key != _filtersKey(app.filters)) _loadNearby();
    }
  }

  /// Near the end of the list: load the next page.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) _loadNearby(more: true);
    return false;
  }

  /// The first page as it is now: people not in the list, or in it and
  /// only now online, wait in [_arrived].
  Future<void> _checkArrived() async {
    final explore = ServicesScope.exploreOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final shownList = app.nearby;
    if (explore == null || token == null || shownList == null || _loading) {
      return;
    }
    final key = _filtersKey(app.filters);
    final page =
        await explore.fetchNearby(token, offset: 0, filters: app.filters);
    // the list changed meanwhile (other filters, loaded again): not now
    if (!mounted ||
        key != _filtersKey(app.filters) ||
        !identical(shownList, app.nearby)) {
      return;
    }
    final now = DateTime.now();
    final shown = {for (final p in shownList) p.id: p};
    final waiting = {for (final p in _arrived) p.id};
    var someoneNew = _someoneNew;
    final arrived = <Profile>[];
    for (final p in page.people) {
      if (waiting.contains(p.id)) continue;
      final before = shown[p.id];
      if (before == null) {
        arrived.add(p);
        someoneNew = true;
      } else if (!before.onlineNowAt(now) && p.onlineNowAt(now)) {
        arrived.add(p);
      }
    }
    if (arrived.isEmpty) return;
    setState(() {
      _arrived = [...arrived, ..._arrived];
      _someoneNew = someoneNew;
    });
  }

  /// The pill tapped: up to the top, and the list again with them.
  Future<void> _showArrived() async {
    setState(() {
      _arrived = const [];
      _someoneNew = false;
    });
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic));
    }
    await _loadNearby();
  }

  @override
  void dispose() {
    _reload?.cancel();
    _watch.stop();
    _scroll.dispose();
    super.dispose();
  }

  /// Their profile, in a pager over everyone shown (swipe to the next).
  void _open(Profile p) {
    final app = AppScope.read(context);
    final people = app.visibleProfiles;
    final index = people.indexWhere((other) => other.id == p.id);
    final ids = index < 0 ? [p.id] : [for (final other in people) other.id];
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfilePager(
            profileIds: ids,
            initialIndex: index < 0 ? 0 : index,
            onShow: (id) {
              final shown = app.profileById(id);
              if (shown != null) _loadPerson(shown);
            })));
    _loadPerson(p);
  }

  /// A real person's full profile (all their photos); the profile screen
  /// shows the list's version until it arrives, and keeps it if this fails.
  Future<void> _loadPerson(Profile p) async {
    final explore = ServicesScope.exploreOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final userId = p.backendId;
    if (explore == null || token == null || userId == null) return;
    try {
      app.updateNearbyPerson(await explore.fetchPerson(token, userId));
    } catch (error) {
      debugPrint('Profile $userId could not be loaded: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = app.filters;
    // new filters (or order): the list again from the top, from the
    // backend
    final key = _filtersKey(f);
    if (_started && _loadedFilters != null && key != _loadedFilters) {
      _loadedFilters = key;
      _reload?.cancel();
      _reload = Timer(Duration.zero, () {
        if (mounted) _loadNearby();
      });
    }
    final people = app.visibleProfiles;
    final onBackend = ServicesScope.exploreOf(context) != null;
    // On the backend, nothing is shown until real people are loaded.
    final waiting = onBackend && app.nearby == null;
    final favorites = app.favoriteProfiles;
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final layout = app.exploreLayoutFor(MediaQuery.sizeOf(context).width);
    // the chosen number across on a phone; more on wider screens, so the
    // cards keep about the same size
    final columns = (layout.columns * width / 430)
        .floor()
        .clamp(layout.columns, layout.columns * 3);
    // the small cards (3 or 4 across): one wall of pictures, edge to edge,
    // with no space between them and square corners
    final wall = layout.wall;
    final gap = wall ? 0.0 : 12.0;
    final side = wall ? 0.0 : 16.0;
    final grid = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      // rows have a fixed height; cards keep their shape
      mainAxisExtent: layout == ExploreLayout.one ? 136 : null,
      // the small cards taller than wide, like portraits
      // the wall's cards tall, like portraits
      childAspectRatio: wall ? 0.62 : 0.8,
    );

    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: HuntrColors.accentGradient.createShader,
                  child: Text('Explore',
                      style: text.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'All filters',
            style: _roundButton,
            icon: Badge(
              isLabelVisible: !f.isDefault,
              smallSize: 8,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => _showFilters(context),
          ),
        ],
      ),
    );
    final Widget quickFilters = SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          PillChip(
            leading: const OnlineDot(size: 10),
            label: 'Online now',
            selected: f.onlineOnly,
            onSelected: (v) => app.filters = f.copyWith(onlineOnly: v),
          ),
          const SizedBox(width: 8),
          PillChip(
            key: const Key('hasPlaceChip'),
            icon: Icons.home_rounded,
            label: 'Has a place',
            selected: f.hasPlace,
            onSelected: (v) => app.filters = f.copyWith(hasPlace: v),
          ),
          const SizedBox(width: 8),
          PillChip(
            key: const Key('favoritesChip'),
            icon: Icons.star_rounded,
            label: 'Favorites',
            selected: f.favoritesOnly,
            onSelected: (v) => app.filters = f.copyWith(favoritesOnly: v),
          ),
          const SizedBox(width: 8),
          LookingForDropdown(
            chosen: f.lookingFor,
            onChanged: (next) => app.filters = f.copyWith(lookingFor: next),
          ),
          const SizedBox(width: 8),
          if (!f.isDefault)
            ActionChip(
              avatar: const Icon(Icons.close, size: 18),
              label: const Text('Clear'),
              onPressed: () => app.filters = const ExploreFilters(),
            ),
        ],
      ),
    );

    // ---- floating, bottom right: the map, or back to the list ----
    final Widget? mapToggle = onBackend && mapEnabled
        ? SizedBox(
            height: 44,
            child: FloatingActionButton.extended(
              key: const Key('exploreMapToggle'),
              tooltip: _mapView ? 'Show the list' : 'Show the map',
              backgroundColor: HuntrColors.orange,
              foregroundColor: Colors.black,
              elevation: 6,
              // a light edge keeps it clear on the dark map and the photos
              shape: StadiumBorder(
                  side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35), width: 1)),
              extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
              onPressed: () => setState(() => _mapView = !_mapView),
              // what it shows next: the map (a pin) or the list (a grid);
              // the icon and word turn into the other ones
              label: AnimatedSwitcher(
                duration: _switchDuration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Row(
                  key: ValueKey(_mapView),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        _mapView
                            ? Icons.grid_view_rounded
                            : Icons.location_on_rounded,
                        size: 20),
                    const SizedBox(width: 6),
                    Text(_mapView ? 'List' : 'Map',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
              ),
            ),
          )
        : null;

    // ---- the map: the same header and quick filters, then the map ----
    Widget? map;
    if (_mapView && onBackend && mapEnabled) {
      map = SafeArea(
          key: const ValueKey('exploreMapView'),
          bottom: false,
          child: Column(children: [
            header,
            quickFilters,
            Expanded(
              child: ExploreMap(
                  explore: ServicesScope.exploreOf(context)!,
                  onOpen: _open,
                  // the zoom buttons sit above the floating List button
                  controlsBottom: 76),
            ),
          ]));
    }

    // the list and the map fade and settle into each other
    final Widget body = AnimatedSwitcher(
      duration: _switchDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: map ??
          SafeArea(
            key: const ValueKey('exploreListView'),
            bottom: false,
            child: RefreshIndicator(
              onRefresh: onBackend ? _loadNearby : app.refresh,
              color: HuntrColors.orange,
              child: NotificationListener<ScrollNotification>(
                onNotification: onBackend ? _onScroll : null,
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    // ---- header ----
                    SliverToBoxAdapter(
                        child: KeyedSubtree(key: _listHeader, child: header)),

                    // ---- the website: get the app, asked in a dialog
                    // (nothing in the apps) ----
                    const SliverToBoxAdapter(child: InstallInvite()),

                    // ---- stories: Add Story, Your Story, then people nearby ----
                    if (onBackend && !waiting)
                      if ((
                        ServicesScope.storiesOf(context),
                        ServicesScope.exploreOf(context)
                      )
                          case (final stories?, final explore?))
                        SliverToBoxAdapter(
                          child: StoryTray(
                              key: ValueKey('tray-$_trayGeneration'),
                              service: stories,
                              explore: explore),
                        ),

                    // ---- quick filters ----
                    SliverToBoxAdapter(child: quickFilters),

                    // ---- favorites row ----
                    if (favorites.isNotEmpty && f.isDefault) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                          child: Text('Your favorites',
                              style: text.titleSmall
                                  ?.copyWith(color: HuntrColors.muted)),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 86,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: favorites.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 14),
                            itemBuilder: (_, i) {
                              final p = favorites[i];
                              return InkWell(
                                borderRadius: BorderRadius.circular(40),
                                onTap: () => _open(p),
                                child: Column(children: [
                                  Avatar(profile: p, size: 58),
                                  const SizedBox(height: 4),
                                  Text(p.name, style: text.labelSmall),
                                ]),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    // ---- grid ----
                    if (waiting && _loadError != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        sliver: SliverToBoxAdapter(
                          child: LoadFailedCard(
                            title: "Couldn't load people nearby",
                            message: _loadError!,
                            onRetry: _loadNearby,
                            retryKey: const Key('exploreRetry'),
                          ),
                        ),
                      )
                    else if (waiting)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 10, side, 24),
                        sliver: SliverGrid.builder(
                          gridDelegate: grid,
                          itemCount: columns * 3,
                          itemBuilder: (_, __) =>
                              _TilePlaceholder(square: wall),
                        ),
                      )
                    else if (people.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyExplore(
                          filtered: !f.isDefault,
                          onClear: () => app.filters = const ExploreFilters(),
                          onRefresh: onBackend ? _loadNearby : null,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 10, side, 24),
                        sliver: SliverGrid.builder(
                          gridDelegate: grid,
                          itemCount: people.length,
                          itemBuilder: (_, i) => layout == ExploreLayout.one
                              ? ProfileRowTile(
                                  profile: people[i],
                                  favorite: app.isFavorite(people[i].id),
                                  onTap: () => _open(people[i]),
                                )
                              : ProfileTile(
                                  profile: people[i],
                                  favorite: app.isFavorite(people[i].id),
                                  layout: layout,
                                  onTap: () => _open(people[i]),
                                ),
                        ),
                      ),

                    // ---- the next page, as you reach the end ----
                    if (onBackend && !waiting && _loading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else if (onBackend && !waiting && _loadError != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          child: LoadFailedCard(
                            title: "Couldn't load more people",
                            message: _loadError!,
                            onRetry: () => _loadNearby(more: true),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
    if (_arrived.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
    }
    return Scaffold(
      floatingActionButton: mapToggle,
      // new people nearby (or newly online): the pill over the list (the
      // Stack stays either way, so the list and map still fade between them)
      body: Stack(children: [
        body,
        if (onBackend && map == null)
          ListenableBuilder(
            listenable: _scroll,
            builder: (context, pill) => Positioned(
              top: MediaQuery.paddingOf(context).top + _pillTop,
              left: 0,
              right: 0,
              child: pill!,
            ),
            child: Center(
              child: NewItemsPill(
                faces: [
                  for (final p in _arrived)
                    Avatar(profile: p, size: 23, showOnline: false),
                ],
                label: _someoneNew ? 'new nearby' : 'online',
                visible: _arrived.isNotEmpty,
                onTap: _showArrived,
              ),
            ),
          ),
      ]),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FilterSheet(),
    );
  }
}

/// The round, outlined search and filter buttons.
/// Search, map and filters: compact, so the title beside them has room.
/// How long the list and the map take to turn into each other.
const _switchDuration = Duration(milliseconds: 320);

final _roundButton = IconButton.styleFrom(
  fixedSize: const Size(40, 40),
  minimumSize: const Size(40, 40),
  padding: EdgeInsets.zero,
  iconSize: 20,
  side: const BorderSide(color: Color(0xFF353944), width: 1.2),
  backgroundColor: HuntrColors.night.withValues(alpha: 0.4),
);

/// A grey tile while people nearby load.
class _TilePlaceholder extends StatelessWidget {
  const _TilePlaceholder({required this.square});

  /// Square corners, like the wall's cards.
  final bool square;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: square ? null : BorderRadius.circular(18),
      ),
    );
  }
}
