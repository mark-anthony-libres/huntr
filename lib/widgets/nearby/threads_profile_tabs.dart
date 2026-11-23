import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/nearby_service.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../load_more_row.dart';
import '../me/section_states.dart';
import 'nearby_post_card.dart';
import 'thread_list_actions.dart';

/// An anonymous profile's tabs: Feed (threads), Reposts and Mentions (not
/// there yet). Mine: all my live threads and reposts. Someone else's: the
/// ones under the anonymous name they wrote a thread (or comment) with,
/// that I may see - another name of theirs is another profile.
class ThreadsProfileTabs extends StatelessWidget {
  /// My anonymous profile's.
  const ThreadsProfileTabs.mine({super.key})
      : postId = null,
        commentId = null;

  /// The anonymous profile of whoever wrote post [postId] (or its comment
  /// [commentId]).
  const ThreadsProfileTabs.author(
      {super.key, required int this.postId, this.commentId});

  final int? postId;
  final int? commentId;

  bool get _mine => postId == null;

  static const tabs = [
    Tab(key: Key('threadsFeedTab'), text: 'Feed'),
    Tab(key: Key('threadsRepostsTab'), text: 'Reposts'),
    Tab(key: Key('threadsMentionsTab'), text: 'Mentions'),
  ];

  /// The tabs themselves, for the screen's pinned header.
  static Widget bar() => TabBar(
        key: const Key('threadsProfileTabs'),
        tabs: tabs,
        indicatorColor: HuntrColors.orange,
        labelColor: Colors.white,
        unselectedLabelColor: HuntrColors.muted,
        dividerColor: HuntrColors.border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      );

  _LoadThreads _load({required bool reposts}) => _mine
      ? (service, token, offset) => reposts
          ? service.reposts(token, offset: offset)
          : service.mine(token, offset: offset)
      : (service, token, offset) => service.authorThreads(token,
          postId: postId!,
          commentId: commentId,
          reposts: reposts,
          offset: offset);

  @override
  Widget build(BuildContext context) => TabBarView(children: [
        _ThreadsTab(
          key: const Key('threadsFeed'),
          load: _load(reposts: false),
          emptyIcon: Icons.forum_outlined,
          emptyTitle: 'No threads yet',
          emptyMessage: _mine
              ? 'Threads you post show here.'
              : 'Threads they post under this name show here.',
        ),
        _ThreadsTab(
          key: const Key('threadsReposts'),
          load: _load(reposts: true),
          emptyIcon: Icons.repeat_rounded,
          emptyTitle: 'No reposts yet',
          emptyMessage: _mine
              ? "Threads you repost show here. Tap the repost button on "
                  "someone's thread."
              : 'Threads they repost under this name show here.',
        ),
        // not there yet
        const _Padded(
          child: EmptyStateCard(
            key: Key('threadsMentions'),
            icon: Icons.alternate_email_rounded,
            title: 'No mentions yet',
            message: 'Mentions in Threads will show here.',
          ),
        ),
      ]);
}

/// An anonymous profile: [header] (the card, and anything under it), then
/// the tabs, pinned while the threads scroll.
class ThreadsProfileBody extends StatelessWidget {
  const ThreadsProfileBody(
      {super.key, required this.header, required this.tabs});

  final Widget header;
  final ThreadsProfileTabs tabs;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: ThreadsProfileTabs.tabs.length,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: header,
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(pinned: true, delegate: _TabsHeader()),
          ],
          body: tabs,
        ),
      );
}

/// The tabs, kept at the top while the threads scroll.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  static const _height = 48.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(
        color: HuntrColors.night,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: threadsColumnWidth),
            child: ThreadsProfileTabs.bar(),
          ),
        ),
      );

  @override
  bool shouldRebuild(_TabsHeader oldDelegate) => false;
}

typedef _LoadThreads = Future<NearbyFeedPage> Function(
    NearbyService service, String token, int offset);

/// One tab's threads, a page at a time, newest first; each can be hearted,
/// reposted, opened, edited, deleted or reported right here.
class _ThreadsTab extends StatefulWidget {
  const _ThreadsTab({
    super.key,
    required this.load,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final _LoadThreads load;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<_ThreadsTab> createState() => _ThreadsTabState();
}

class _ThreadsTabState extends State<_ThreadsTab>
    with ThreadListActions, AutomaticKeepAliveClientMixin {
  List<NearbyPost>? _posts;
  int? _next = 0;
  bool _loading = false;
  String? _error;

  @override
  List<NearbyPost>? get threads => _posts;
  @override
  set threads(List<NearbyPost>? value) => _posts = value;

  // switching tabs keeps what's loaded
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The first page again, or ([more]) the next one.
  Future<void> _load({bool more = false}) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    final offset = more ? _next : 0;
    if (service == null || token == null || offset == null || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      final page = await widget.load(service, token, offset);
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
      });
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final posts = _posts;
    final now = DateTime.now();
    if (ServicesScope.nearbyOf(context) == null) {
      return _Padded(
        child: EmptyStateCard(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            message: widget.emptyMessage),
      );
    }
    return RefreshIndicator(
      color: HuntrColors.orange,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, box) => ListView(
          padding: threadsColumnPadding(box.maxWidth, top: 12),
          children: [
            if (posts == null && _error != null)
              LoadFailedCard(
                title: "Couldn't load these",
                message: _error!,
                onRetry: _load,
              )
            else if (posts == null)
              const LoadingRows(count: 3, height: 150)
            else if (posts.isEmpty)
              EmptyStateCard(
                  icon: widget.emptyIcon,
                  title: widget.emptyTitle,
                  message: widget.emptyMessage)
            else ...[
              for (final post in posts)
                if (nearbyThreadShown(post))
                  NearbyPostCard(
                    key: ValueKey('myThread-${post.id}'),
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
        ),
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => ListView(
          padding: threadsColumnPadding(box.maxWidth, top: 16),
          children: [child]));
}

/// How wide threads get on a wide screen (as in the Threads feed).
const threadsColumnWidth = 720.0;

/// A list's padding that keeps its threads in a centred column of at most
/// [threadsColumnWidth] of its [width] (16 at the sides on a phone).
EdgeInsets threadsColumnPadding(double width, {required double top}) {
  final side =
      width > threadsColumnWidth + 32 ? (width - threadsColumnWidth) / 2 : 16.0;
  return EdgeInsets.fromLTRB(side, top, side, 24);
}
