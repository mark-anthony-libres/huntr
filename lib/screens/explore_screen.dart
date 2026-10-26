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
import '../widgets/explore/vibe_banner.dart';
import 'profile_pager.dart';
import '../widgets/explore/empty_explore.dart';
import '../widgets/explore/explore_map.dart';
import '../widgets/explore/filter_sheet.dart';
import '../widgets/me/section_states.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  // ---- people nearby, from the backend ----
  bool _started = false;
  bool _loading = false;
  String? _loadError;

  /// Explore as a map instead of the list.
  bool _mapView = false;

  /// A fresh first page of Explore: the stories tray starts over too.
  int _trayGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || ServicesScope.exploreOf(context) == null) return;
    _started = true;
    _loadNearby();
  }

  /// The first page (or, with [more], the next one).
  Future<void> _loadNearby({bool more = false}) async {
    final explore = ServicesScope.exploreOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final offset = more ? app.nearbyNextOffset : 0;
    if (explore == null || token == null || offset == null || _loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await explore.fetchNearby(token, offset: offset);
      app.setNearby(page.people, nextOffset: page.nextOffset, append: more);
      if (!more && mounted) setState(() => _trayGeneration++);
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
    }
  }

  /// Near the end of the list: load the next page.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) _loadNearby(more: true);
    return false;
  }

  @override
  void dispose() {
    _search.dispose();
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
    final people = app.visibleProfiles;
    final onBackend = ServicesScope.exploreOf(context) != null;
    // On the backend, nothing is shown until real people are loaded.
    final waiting = onBackend && app.nearby == null;
    final favorites = app.favoriteProfiles;
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final layout = app.exploreLayout;
    // the chosen number across on a phone; more on wider screens, so the
    // cards keep about the same size
    final columns = (layout.columns * width / 430)
        .floor()
        .clamp(layout.columns, layout.columns * 3);
    final gap = switch (layout) {
      ExploreLayout.one || ExploreLayout.two => 12.0,
      ExploreLayout.three => 8.0,
      ExploreLayout.four => 4.0,
    };
    final grid = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      // rows have a fixed height; cards keep their shape
      mainAxisExtent: layout == ExploreLayout.one ? 136 : null,
      childAspectRatio: layout == ExploreLayout.four ? 0.86 : 0.8,
    );

    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: _searching
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('exploreSearch'),
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search names, bios, interests',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => app.filters = f.copyWith(query: v),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _search.clear();
                    app.filters = app.filters.copyWith(query: '');
                    setState(() => _searching = false);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: HuntrColors.accentGradient.createShader,
                        child: Text('Explore',
                            style: text.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.near_me_rounded,
                            size: 16, color: HuntrColors.orange),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              // the count not until real
                              // people are loaded
                              waiting
                                  ? 'Discover people near you'
                                  : app.onlineCount == 1
                                      ? '1 online near you'
                                      : '${app.onlineCount} online near you',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium
                                  ?.copyWith(color: HuntrColors.muted)),
                        ),
                      ]),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Search',
                  style: _roundButton,
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _searching = true),
                ),
                const SizedBox(width: 6),
                if (onBackend && mapEnabled) ...[
                  IconButton.outlined(
                    key: const Key('exploreMapToggle'),
                    tooltip: _mapView ? 'List' : 'Map',
                    style: _roundButton,
                    icon: Icon(_mapView
                        ? Icons.grid_view_rounded
                        : Icons.map_outlined),
                    onPressed: () => setState(() => _mapView = !_mapView),
                  ),
                  const SizedBox(width: 6),
                ],
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
          // every "looking for" choice, as on profiles
          for (final l in LookingFor.values) ...[
            PillChip(
              icon: l.icon,
              label: l.label,
              selected: f.lookingFor.contains(l),
              onSelected: (v) {
                final next = {...f.lookingFor};
                v ? next.add(l) : next.remove(l);
                app.filters = f.copyWith(lookingFor: next);
              },
            ),
            const SizedBox(width: 8),
          ],
          if (!f.isDefault)
            ActionChip(
              avatar: const Icon(Icons.close, size: 18),
              label: const Text('Clear'),
              onPressed: () {
                _search.clear();
                app.filters = const ExploreFilters();
              },
            ),
        ],
      ),
    );

    // ---- the map: the same header and quick filters, then the map ----
    if (_mapView && onBackend && mapEnabled) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            header,
            quickFilters,
            Expanded(
              child: ExploreMap(
                  explore: ServicesScope.exploreOf(context)!, onOpen: _open),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: onBackend ? _loadNearby : app.refresh,
          color: HuntrColors.orange,
          child: NotificationListener<ScrollNotification>(
            onNotification: onBackend ? _onScroll : null,
            child: CustomScrollView(
              slivers: [
                // ---- header ----
                SliverToBoxAdapter(child: header),

                // ---- the website: get the app (nothing in the apps) ----
                const SliverToBoxAdapter(child: InstallBanner()),

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

                // ---- people who want what I want ----
                if (!waiting && f.isDefault && app.showVibeBanner)
                  SliverToBoxAdapter(
                    child: VibeBanner(
                      people: [
                        for (final p in people)
                          if (p.lookingFor
                              .intersection(app.myLookingFor)
                              .isNotEmpty)
                            p,
                      ],
                      onTap: () => app.filters =
                          f.copyWith(lookingFor: {...app.myLookingFor}),
                      onHide: () => app.showVibeBanner = false,
                    ),
                  ),

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
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    sliver: SliverGrid.builder(
                      gridDelegate: grid,
                      itemCount: columns * 3,
                      itemBuilder: (_, __) => const _TilePlaceholder(),
                    ),
                  )
                else if (people.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyExplore(
                      filtered: !f.isDefault,
                      onClear: () {
                        _search.clear();
                        app.filters = const ExploreFilters();
                      },
                      onRefresh: onBackend ? _loadNearby : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
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
  const _TilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}
