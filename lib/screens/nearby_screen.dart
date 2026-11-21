import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/nearby_service.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/load_more_row.dart';
import '../widgets/me/section_states.dart';
import '../widgets/nearby/nearby_post_card.dart';
import '../widgets/nearby/thread_list_actions.dart';
import '../widgets/new_items_pill.dart';
import '../widgets/anonymous_avatar.dart';
import 'anonymous_profile_screen.dart' show MyAnonymousProfileScreen;
import 'nearby_compose_screen.dart';

/// Threads (in Explore): anonymous posts from people around me - nearest
/// or newest first, optionally only within a distance - and Post to write one.
/// Everyone shows as a random name and animal; the backend decides who
/// sees what (each post's radius from where it was posted).
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => NearbyScreenState();
}

class NearbyScreenState extends State<NearbyScreen> with ThreadListActions {
  bool _latest = false;

  /// Only posts within this of me (null: as far as each post reaches).
  int? _withinM;

  List<NearbyPost>? _posts;

  @override
  List<NearbyPost>? get threads => _posts;
  @override
  set threads(List<NearbyPost>? value) => _posts = value;
  int? _next;
  bool _loading = false;
  String? _error;
  bool _noLocation = false;

  /// While a post's video is being compressed: when its post is looked
  /// at again (it shows once it's ready).
  Timer? _recheck;
  static const _recheckEvery = Duration(seconds: 20);

  final _scroll = ScrollController();

  /// Nearby / Latest / Distance and +: the pill sits under them at the top.
  final _filtersRow = GlobalKey();

  /// Where their row ends in the list, measured once it's laid out.
  double _filtersBottom = 0;

  void _measureFilters() {
    final box = _filtersRow.currentContext?.findRenderObject();
    if (!mounted || box is! RenderBox || !box.hasSize) return;
    // the list's top padding, then the row
    final bottom = 12 + box.size.height + 6;
    if (bottom != _filtersBottom) setState(() => _filtersBottom = bottom);
  }

  /// Where the pill sits: under the filters while they show, then at the
  /// top as the list scrolls (like X's under its own bar).
  double get _pillTop {
    final scrolled = _scroll.hasClients ? _scroll.offset : 0.0;
    return (_filtersBottom - scrolled).clamp(8.0, double.infinity);
  }

  /// Threads posted since the list loaded, not shown yet (the "posted" pill
  /// at the top; tapped, the list starts over with them).
  List<NearbyPost> _newer = const [];
  late final _watch =
      NewItemsWatch(context: context, every: _newerEvery, check: _checkNewer);
  static const _newerEvery = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _watch.start();
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _watch.stop();
    _scroll.dispose();
    super.dispose();
  }

  /// The first page as it is now: threads newer than the newest shown,
  /// from someone else, wait in [_newer].
  Future<void> _checkNewer() async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    final posts = _posts;
    if (service == null || token == null || posts == null || _loading) {
      return;
    }
    final page = await service.feed(token,
        sort: _latest ? 'latest' : 'nearby', withinM: _withinM, offset: 0);
    if (!mounted || !identical(posts, _posts)) return;
    final shown = {for (final p in posts) p.id};
    final waiting = {for (final p in _newer) p.id};
    final newest = posts.isEmpty
        ? null
        : posts.map((p) => p.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final arrived = [
      for (final p in page.posts)
        if (!p.mine &&
            !shown.contains(p.id) &&
            !waiting.contains(p.id) &&
            (newest == null || p.createdAt.isAfter(newest)))
          p,
    ];
    if (arrived.isNotEmpty) setState(() => _newer = [...arrived, ..._newer]);
  }

  /// The pill tapped: up to the top, and the list again with them.
  Future<void> _showNewer() async {
    setState(() => _newer = const []);
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic));
    }
    await _load();
  }

  /// Who posted them: one face each, newest first.
  List<Widget> get _newerFaces {
    final seen = <String>{};
    return [
      for (final p in _newer)
        if (seen.add(p.official ? 'huntr' : p.author.avatar))
          p.official
              ? const HuntrPostAvatar(size: 23)
              : AnonymousArt(animal: p.author.avatar, radius: 11.5, size: 23),
    ];
  }

  /// Looks again soon at posts whose video is still processing.
  void _watchProcessing() {
    if (_recheck?.isActive ?? false) return;
    if (!(_posts ?? const <NearbyPost>[]).any((p) => p.mediaProcessing)) {
      return;
    }
    _recheck = Timer(_recheckEvery, _recheckProcessing);
  }

  Future<void> _recheckProcessing() async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (!mounted || service == null || token == null) return;
    for (final post in [...?_posts]) {
      if (!post.mediaProcessing) continue;
      try {
        final now = (await service.discussion(token, post.id)).post;
        if (!mounted) return;
        setState(() => _posts = [
              for (final p in _posts ?? const <NearbyPost>[])
                p.id == now.id ? now : p,
            ]);
      } catch (error) {
        debugPrint('Thread ${post.id} not checked again: $error');
      }
    }
    if (mounted) _watchProcessing();
  }

  /// The first page again, or ([more]) the next one.
  Future<void> _load({bool more = false}) async {
    final service = ServicesScope.nearbyOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final offset = more ? _next : 0;
    if (service == null || token == null || offset == null || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      final page = await service.feed(token,
          sort: _latest ? 'latest' : 'nearby',
          withinM: _withinM,
          offset: offset);
      if (!mounted) return;
      final known = {
        if (more)
          for (final p in _posts ?? const <NearbyPost>[]) p.id
      };
      setState(() {
        _posts = [
          if (more) ...?_posts,
          for (final p in page.posts)
            if (!known.contains(p.id)) p,
        ];
        _next = page.nextOffset;
        _noLocation = false;
        if (!more) _newer = const [];
      });
      _watchProcessing();
    } on SessionRejectedException {
      if (mounted) app.endSession();
    } on NearbyNoLocationException {
      if (mounted) setState(() => _noLocation = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sort(bool latest) {
    if (latest == _latest) return;
    setState(() {
      _latest = latest;
      _posts = null;
    });
    _load();
  }

  Future<void> _pickWithin() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Show posts within',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final m in [0, ...NearbyService.radii])
            ListTile(
              key: Key('nearbyWithin-$m'),
              title: Text(
                  m == 0 ? 'Anywhere they reach me' : nearbyRadiusLabel(m)),
              trailing: (_withinM ?? 0) == m
                  ? Icon(Icons.check_rounded, color: HuntrColors.orange)
                  : null,
              onTap: () => Navigator.of(context).pop(m),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _withinM = picked == 0 ? null : picked;
      _posts = null;
    });
    unawaited(_load());
  }

  /// Write a thread (the + beside the filters, or the floating one once the
  /// feed is scrolled); not while the location is missing.
  void compose() {
    if (!_noLocation) _compose();
  }

  Future<void> _compose() async {
    final posted = await Navigator.of(context).push<NearbyPost>(
        MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NearbyComposeScreen()));
    if (posted == null || !mounted) return;
    setState(() => _posts = [posted, ...?_posts]);
    _watchProcessing();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text('Posted as ${posted.author.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    final now = DateTime.now();
    return RefreshIndicator(
      color: HuntrColors.orange,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, box) {
          // a centred column on a wide screen, like Taps
          final side = box.maxWidth > 752 ? (box.maxWidth - 720) / 2 : 16.0;
          final list = ListView(
            key: const Key('nearbyList'),
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(side, 12, side, 24),
            children: [
              // ---- nearest or newest, and how far: one line, a little
              // smaller when the screen is narrow ----
              KeyedSubtree(
                key: _filtersRow,
                child: Row(children: [
                  Expanded(
                    child: FittedBox(
                      key: const Key('nearbyFilters'),
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(children: [
                        for (final (latest, label, key) in const [
                          (false, 'Nearby', 'nearbySortNearby'),
                          (true, 'Latest', 'nearbySortLatest'),
                        ]) ...[
                          ChoiceChip(
                            key: Key(key),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            label: Text(label),
                            selected: _latest == latest,
                            showCheckmark: false,
                            onSelected: (_) => _sort(latest),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ActionChip(
                          key: const Key('nearbyWithin'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          avatar:
                              const Icon(Icons.location_on_outlined, size: 16),
                          label: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_withinM == null
                                ? 'Distance'
                                : nearbyRadiusLabel(_withinM!)),
                            const Icon(Icons.expand_more_rounded, size: 16),
                          ]),
                          onPressed: _pickWithin,
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // + to write one
                  IconButton.filled(
                    key: const Key('nearbyCompose'),
                    tooltip: 'New thread',
                    style: IconButton.styleFrom(
                        backgroundColor: HuntrColors.orange,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(40, 40)),
                    onPressed: _noLocation ? null : _compose,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // ---- the feed, or why not ----
              if (ServicesScope.nearbyOf(context) == null)
                const EmptyStateCard(
                    icon: Icons.theater_comedy_outlined,
                    title: 'Threads',
                    message: 'Sign in to see threads from people around you.')
              else if (_noLocation)
                EmptyStateCard(
                  key: const Key('nearbyNoLocation'),
                  icon: Icons.location_off_outlined,
                  title: 'Where are you?',
                  message: 'Threads shows posts from people around you, so '
                      'it needs your location. Turn it on, then try again.',
                  actionLabel: 'Try again',
                  onAction: _load,
                )
              else if (posts == null && _error != null)
                LoadFailedCard(
                  title: "Couldn't load Threads",
                  message: _error!,
                  onRetry: _load,
                  retryKey: const Key('nearbyRetry'),
                )
              else if (posts == null)
                const LoadingRows(count: 4, height: 150)
              else if (posts.isEmpty)
                EmptyStateCard(
                  key: const Key('nearbyEmpty'),
                  icon: Icons.theater_comedy_outlined,
                  title: 'No threads nearby',
                  message: 'Start one and people near you will see it.',
                  actionLabel: 'Start a thread',
                  onAction: _compose,
                )
              else ...[
                for (final post in posts)
                  NearbyPostCard(
                    key: ValueKey('nearbyCard-${post.id}'),
                    post: post,
                    now: now,
                    onLike: () => likeThread(post),
                    onRepost: () => repostThread(post),
                    onAction: (action) => actOnThread(post, action),
                    onOpen: () => openThread(post),
                    onAuthor: () => openThreadAuthor(post),
                  ),
                if (_next != null)
                  LoadMoreRow(onVisible: () => _load(more: true)),
              ],
            ],
          );
          if (_newer.isNotEmpty) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _measureFilters());
          }
          // newer threads than the list shows: the pill over its top
          return Stack(children: [
            list,
            ListenableBuilder(
              listenable: _scroll,
              builder: (context, pill) => Positioned(
                top: _pillTop,
                left: 0,
                right: 0,
                child: pill!,
              ),
              child: Center(
                child: NewItemsPill(
                  faces: _newerFaces,
                  label: 'posted',
                  visible: _newer.isNotEmpty,
                  onTap: _showNewer,
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// The Threads tab: its title (like the other tabs'), then [NearbyScreen].
/// Scrolling the feed makes the header smaller: the description hides and
/// the title, bell and my animal shrink; back at the top it's full again.
class ThreadsTab extends StatefulWidget {
  const ThreadsTab({super.key});

  @override
  State<ThreadsTab> createState() => _ThreadsTabState();
}

class _ThreadsTabState extends State<ThreadsTab> {
  bool _compact = false;
  final _feed = GlobalKey<NearbyScreenState>();

  /// Scrolled this far: smaller. Back above [_expandAt]: full again (the
  /// gap keeps it from flickering at the edge).
  static const _compactAt = 24.0;
  static const _expandAt = 8.0;

  bool _scrolled(ScrollNotification n) {
    // only the feed itself (not a photo carousel inside a post)
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final y = n.metrics.pixels;
    final compact = _compact ? y > _expandAt : y > _compactAt;
    if (compact != _compact) setState(() => _compact = compact);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final full = text.headlineMedium?.fontSize ?? 28;
    return Scaffold(
      // scrolled (the + beside the filters gone by): a floating + to post
      floatingActionButton: IgnorePointer(
        ignoring: !_compact,
        child: AnimatedScale(
          scale: _compact ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: _compact ? Curves.easeOutBack : Curves.easeIn,
          child: FloatingActionButton(
            key: const Key('threadsFloatingCompose'),
            tooltip: 'New thread',
            shape: const CircleBorder(),
            backgroundColor: HuntrColors.orange,
            foregroundColor: Colors.black,
            // a light lift, no dark ring around it
            elevation: 2,
            highlightElevation: 4,
            onPressed: () => _feed.currentState?.compose(),
            child: const Icon(Icons.add_rounded, size: 30),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 0: full size; 1: compact
          TweenAnimationBuilder<double>(
            key: const Key('threadsHeader'),
            tween: Tween(end: _compact ? 1 : 0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, t, _) => Padding(
              padding: EdgeInsets.fromLTRB(20, lerpDouble(12, 6, t)!, 16, 0),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback:
                              HuntrColors.accentGradient.createShader,
                          child: Text('Threads',
                              style: text.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: lerpDouble(full, 22, t),
                                  color: Colors.white)),
                        ),
                        // the description folds away
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topLeft,
                            heightFactor: 1 - t,
                            child: Opacity(
                              opacity: 1 - t,
                              child: const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                    'Anonymous posts from people around you',
                                    key: Key('threadsDescription'),
                                    style: TextStyle(color: HuntrColors.muted)),
                              ),
                            ),
                          ),
                        ),
                      ]),
                ),
                // notifications: not working yet, only its place
                IconButton(
                  key: const Key('threadsNotifications'),
                  tooltip: 'Notifications',
                  onPressed: () {},
                  icon: Icon(Icons.notifications_none_rounded,
                      size: lerpDouble(28, 22, t)),
                ),
                Container(
                    width: 1,
                    height: lerpDouble(28, 20, t),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: HuntrColors.border),
                _MyAnonymousButton(size: lerpDouble(46, 34, t)!),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _scrolled,
              child: NearbyScreen(key: _feed),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Me in Threads: my anonymous animal (never my photo); tapped, my
/// anonymous profile.
class _MyAnonymousButton extends StatelessWidget {
  const _MyAnonymousButton({required this.size});

  /// Across (smaller once the feed is scrolled).
  final double size;

  @override
  Widget build(BuildContext context) {
    final mine = AppScope.of(context).anonymousName;
    return Tooltip(
      message: mine == null ? 'My anonymous profile' : mine.name,
      child: InkWell(
        key: const Key('threadsMyAnonymous'),
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const MyAnonymousProfileScreen())),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: [
            AnonymousArt(
                animal: mine?.avatar ?? 'fox', radius: size / 2, size: size),
            // I'm here (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: HuntrColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: HuntrColors.night, width: 2),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
