import 'dart:async';

import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/nearby_service.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/load_more_row.dart';
import '../widgets/me/section_states.dart';
import '../widgets/nearby/nearby_post_card.dart';
import 'nearby_compose_screen.dart';
import 'nearby_post_screen.dart';

/// Threads (in Explore): anonymous posts from people around me - nearest
/// or newest first, optionally only within a distance - and Post to write one.
/// Everyone shows as a random name and animal; the backend decides who
/// sees what (each post's radius from where it was posted).
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  bool _latest = false;

  /// Only posts within this of me (null: as far as each post reaches).
  int? _withinM;

  List<NearbyPost>? _posts;
  int? _next;
  bool _loading = false;
  String? _error;
  bool _noLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      });
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

  Future<void> _compose() async {
    final posted = await Navigator.of(context).push<NearbyPost>(
        MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const NearbyComposeScreen()));
    if (posted == null || !mounted) return;
    setState(() => _posts = [posted, ...?_posts]);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text('Posted as ${posted.author.name} 🎭')));
  }

  Future<void> _open(NearbyPost post) async {
    final updated = await Navigator.of(context).push<NearbyPost?>(
        MaterialPageRoute(builder: (_) => NearbyPostScreen(post: post)));
    if (!mounted) return;
    // a deleted or no-longer-visible post leaves; otherwise its counts
    setState(() => _posts = [
          for (final p in _posts ?? const <NearbyPost>[])
            if (p.id != post.id) p else if (updated != null) updated,
        ]);
  }

  Future<void> _like(NearbyPost post) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) return;
    // at once; corrected (or undone) by the answer
    _replace(post.copyWith(
        liked: !post.liked, likeCount: post.likeCount + (post.liked ? -1 : 1)));
    try {
      final result = await service.like(token, post.id, like: !post.liked);
      _replace(post.copyWith(likeCount: result.count, liked: result.liked));
    } catch (error) {
      _replace(post);
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  Future<void> _act(NearbyPost post, NearbyAction action) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) return;
    try {
      if (action == NearbyAction.delete) {
        final sure = await _confirmDelete();
        if (!sure) return;
        await service.delete(token, postId: post.id);
        _say('Post deleted.');
      } else {
        final reason = await askReportReason(context);
        if (reason == null) return;
        await service.report(token, post.id, reason: reason);
        _say("Thanks. It's reported, and you won't see it anymore.");
      }
      if (mounted) {
        setState(() => _posts = [
              for (final p in _posts ?? const <NearbyPost>[])
                if (p.id != post.id) p
            ]);
      }
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  /// The post author's anonymous profile: Report there reports it here.
  Future<void> _openAuthor(NearbyPost post) async {
    final action = await openThreadsAuthor(context,
        author: post.author,
        postId: post.id,
        distanceM: post.distanceM,
        mine: post.mine);
    if (action != null && mounted) await _act(post, action);
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this post?'),
          content: const Text('Its comments go with it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            TextButton(
                key: const Key('nearbyConfirmDelete'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete',
                    style: TextStyle(color: HuntrColors.coral))),
          ],
        ),
      ) ??
      false;

  void _replace(NearbyPost post) {
    if (!mounted) return;
    setState(() => _posts = [
          for (final p in _posts ?? const <NearbyPost>[])
            p.id == post.id ? post : p
        ]);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
          return ListView(
            key: const Key('nearbyList'),
            padding: EdgeInsets.fromLTRB(side, 12, side, 24),
            children: [
              // ---- nearest or newest, and how far (a second line when
              // the screen is narrow) ----
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
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
                            selectedColor:
                                HuntrColors.orange.withValues(alpha: 0.18),
                            side: BorderSide(
                                color: _latest == latest
                                    ? HuntrColors.orange
                                    : HuntrColors.border),
                            onSelected: (_) => _sort(latest),
                          ),
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
                  title: 'Quiet around here',
                  message: 'No threads near you yet. Be the first: say '
                      'something to the people around you.',
                  actionLabel: 'Start a thread',
                  onAction: _compose,
                )
              else ...[
                for (final post in posts)
                  NearbyPostCard(
                    key: ValueKey('nearbyCard-${post.id}'),
                    post: post,
                    now: now,
                    onLike: () => _like(post),
                    onAction: (action) => _act(post, action),
                    onOpen: () => _open(post),
                    onAuthor: () => _openAuthor(post),
                  ),
                if (_next != null)
                  LoadMoreRow(onVisible: () => _load(more: true)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The Threads tab: its title (like the other tabs'), then [NearbyScreen].
class ThreadsTab extends StatelessWidget {
  const ThreadsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShaderMask(
                shaderCallback: HuntrColors.accentGradient.createShader,
                child: Text('Threads',
                    style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(height: 2),
              const Text('Anonymous posts from people around you',
                  style: TextStyle(color: HuntrColors.muted)),
            ]),
          ),
          const SizedBox(height: 6),
          const Expanded(child: NearbyScreen()),
        ]),
      ),
    );
  }
}
