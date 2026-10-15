import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/profile_tile.dart';
import 'profile_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Profile p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(profileId: p.id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = app.filters;
    final people = app.visibleProfiles;
    final favorites = app.favoriteProfiles;
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 6 : width >= 600 ? 4 : 3;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: app.refresh,
          color: HuntrColors.amber,
          child: CustomScrollView(
            slivers: [
              // ---- header ----
              SliverToBoxAdapter(
                child: Padding(
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
                                        style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                                  ),
                                  Row(children: [
                                    const OnlineDot(size: 9),
                                    const SizedBox(width: 6),
                                    Text('${app.onlineCount} people online near you',
                                        style: text.bodySmall?.copyWith(color: HuntrColors.muted)),
                                  ]),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Search',
                              icon: const Icon(Icons.search),
                              onPressed: () => setState(() => _searching = true),
                            ),
                            IconButton(
                              tooltip: 'All filters',
                              icon: Badge(
                                isLabelVisible: !f.isDefault,
                                smallSize: 8,
                                child: const Icon(Icons.tune),
                              ),
                              onPressed: () => _showFilters(context),
                            ),
                          ],
                        ),
                ),
              ),

              // ---- quick filters ----
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: [
                      FilterChip(
                        avatar: const OnlineDot(size: 10),
                        label: const Text('Online now'),
                        selected: f.onlineOnly,
                        showCheckmark: false,
                        onSelected: (v) => app.filters = f.copyWith(onlineOnly: v),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.near_me_outlined, size: 18),
                        label: const Text('Within 5 km'),
                        selected: f.maxDistanceKm != null,
                        showCheckmark: false,
                        onSelected: (v) => app.filters =
                            v ? f.copyWith(maxDistanceKm: 5) : f.copyWith(clearDistance: true),
                      ),
                      const SizedBox(width: 8),
                      for (final l in [LookingFor.chat, LookingFor.friends, LookingFor.dates]) ...[
                        FilterChip(
                          avatar: Icon(l.icon, size: 18),
                          label: Text(l.label),
                          selected: f.lookingFor.contains(l),
                          showCheckmark: false,
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
                ),
              ),

              // ---- favorites row ----
              if (favorites.isNotEmpty && f.isDefault) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Text('Your favorites', style: text.titleSmall?.copyWith(color: HuntrColors.muted)),
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
              if (people.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyExplore(onClear: () {
                    _search.clear();
                    app.filters = const ExploreFilters();
                  }),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: people.length,
                    itemBuilder: (_, i) => ProfileTile(
                      profile: people[i],
                      favorite: app.isFavorite(people[i].id),
                      onTap: () => _open(people[i]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _EmptyExplore extends StatelessWidget {
  const _EmptyExplore({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.travel_explore, size: 56, color: HuntrColors.muted),
          const SizedBox(height: 12),
          Text('Nobody matches these filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Try widening the distance or age range.', style: TextStyle(color: HuntrColors.muted)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ExploreFilters f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    f = AppScope.read(context).filters;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dist = f.maxDistanceKm ?? 25;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Online now only'),
              value: f.onlineOnly,
              onChanged: (v) => setState(() => f = f.copyWith(onlineOnly: v)),
            ),
            const SizedBox(height: 8),
            Text('Distance: ${f.maxDistanceKm == null ? 'Any' : 'up to ${dist.round()} km'}', style: text.titleSmall),
            Slider(
              value: dist,
              min: 1,
              max: 25,
              divisions: 24,
              label: dist >= 25 ? 'Any' : '${dist.round()} km',
              onChanged: (v) => setState(
                  () => f = v >= 25 ? f.copyWith(clearDistance: true) : f.copyWith(maxDistanceKm: v)),
            ),
            Text('Age: ${f.ageRange.start.round()} - ${f.ageRange.end.round()}${f.ageRange.end >= 60 ? '+' : ''}',
                style: text.titleSmall),
            RangeSlider(
              values: f.ageRange,
              min: 18,
              max: 60,
              divisions: 42,
              onChanged: (v) => setState(() => f = f.copyWith(ageRange: v)),
            ),
            const SizedBox(height: 4),
            Text('Looking for', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in LookingFor.values)
                  FilterChip(
                    avatar: Icon(l.icon, size: 18),
                    label: Text(l.label),
                    showCheckmark: false,
                    selected: f.lookingFor.contains(l),
                    onSelected: (v) {
                      final next = {...f.lookingFor};
                      v ? next.add(l) : next.remove(l);
                      setState(() => f = f.copyWith(lookingFor: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => f = ExploreFilters(query: f.query)),
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    AppScope.read(context).filters = f;
                    Navigator.pop(context);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Show results'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
