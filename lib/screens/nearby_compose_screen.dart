import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/nearby_service.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/load_more_row.dart';
import '../widgets/nearby/nearby_post_card.dart';
import '../widgets/nearby/nearby_tags.dart';
import 'chats_screen.dart' show timeLabel;
import 'nearby_post_screen.dart';

/// New thread: what's on my mind (up to [NearbyService.maxLength]
/// characters) and how far it reaches, then Post - it goes up under a random
/// name and animal. Below, my live threads (open one, or delete it). Pops
/// with the new thread once it's up.
class NearbyComposeScreen extends StatefulWidget {
  const NearbyComposeScreen({super.key});

  @override
  State<NearbyComposeScreen> createState() => _NearbyComposeScreenState();
}

class _NearbyComposeScreenState extends State<NearbyComposeScreen> {
  final _text = TextEditingController();

  /// How far it reaches, in metres (one of [NearbyService.radii]).
  int _radiusM = 5000;

  /// The tags picked (ids), and the tags there are (once loaded).
  Set<int> _tagIds = {};
  List<NearbyTagCategory>? _tagCategories;
  bool _posting = false;
  String? _error;

  /// My live threads (null: loading), and where the next page starts.
  List<NearbyPost>? _mine;
  int? _next;
  bool _loadingMine = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMine());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadMine({bool more = false}) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    final offset = more ? _next : 0;
    if (service == null || token == null || offset == null || _loadingMine) {
      return;
    }
    _loadingMine = true;
    try {
      final page = await service.mine(token, offset: offset);
      if (!mounted) return;
      setState(() {
        _mine = [if (more) ...?_mine, ...page.posts];
        _next = page.nextOffset;
      });
    } catch (error) {
      debugPrint('My threads not loaded: $error');
      if (mounted && _mine == null) setState(() => _mine = const []);
    } finally {
      _loadingMine = false;
    }
  }

  bool get _ready =>
      _text.text.trim().isNotEmpty &&
      _text.text.length <= NearbyService.maxLength;

  Future<void> _post() async {
    final service = ServicesScope.nearbyOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (!_ready || _posting || service == null || token == null) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      final post = await service.post(token,
          body: _text.text, radiusM: _radiusM, tagIds: _tagIds.toList());
      if (mounted) Navigator.of(context).pop(post);
    } on SessionRejectedException {
      if (mounted) app.endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : "Your thread didn't go up. Check your connection and try "
                'again.');
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// The tags there are (loaded once, the first time they're picked).
  Future<List<NearbyTagCategory>> _loadTags() async {
    if (_tagCategories case final loaded?) return loaded;
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) throw StateError('signed out');
    final loaded = await service.tags(token);
    if (mounted) setState(() => _tagCategories = loaded);
    return loaded;
  }

  Future<void> _pickTags() async {
    final picked =
        await pickNearbyTags(context, load: _loadTags, picked: _tagIds);
    if (picked != null && mounted) setState(() => _tagIds = picked);
  }

  /// The picked tags' names, in the order they're listed.
  List<String> get _tagNames => [
        for (final category in _tagCategories ?? const <NearbyTagCategory>[])
          for (final tag in category.tags)
            if (_tagIds.contains(tag.id)) tag.name,
      ];

  Future<void> _pickRadius() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Who can see it',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Only people this close to where you post.',
                style: TextStyle(color: HuntrColors.muted)),
          ),
          for (final m in NearbyService.radii)
            ListTile(
              key: Key('nearbyRadius-$m'),
              leading: const Icon(Icons.location_on_outlined),
              title: Text('Within ${nearbyRadiusLabel(m)}'),
              trailing: m == _radiusM
                  ? Icon(Icons.check_rounded, color: HuntrColors.orange)
                  : null,
              onTap: () => Navigator.of(context).pop(m),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null && mounted) setState(() => _radiusM = picked);
  }

  Future<void> _open(NearbyPost post) async {
    final updated = await Navigator.of(context).push<NearbyPost?>(
        MaterialPageRoute(builder: (_) => NearbyPostScreen(post: post)));
    if (!mounted) return;
    setState(() => _mine = [
          for (final p in _mine ?? const <NearbyPost>[])
            if (p.id != post.id) p else if (updated != null) updated,
        ]);
  }

  Future<void> _act(NearbyPost post, NearbyAction action) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null || action != NearbyAction.delete) {
      return;
    }
    final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this thread?'),
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
    if (!sure) return;
    try {
      await service.delete(token, postId: post.id);
      if (!mounted) return;
      setState(() => _mine = [
            for (final p in _mine ?? const <NearbyPost>[])
              if (p.id != post.id) p
          ]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is BackendException
              ? error.message
              : "That didn't go through.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _text.text.length;
    final over = count > NearbyService.maxLength;
    final mine = _mine;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('nearbyComposeClose'),
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New thread'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('nearbyPost'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 22)),
              onPressed: _ready && !_posting ? _post : null,
              child: _posting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // ---- what's on my mind ----
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: Column(children: [
                    TextField(
                      key: const Key('nearbyText'),
                      controller: _text,
                      autofocus: true,
                      minLines: 4,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        hintText: "What's on your mind?",
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('$count/${NearbyService.maxLength}',
                          key: const Key('nearbyCount'),
                          style: TextStyle(
                              color:
                                  over ? HuntrColors.coral : HuntrColors.muted,
                              fontSize: 13)),
                    ),
                  ]),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!,
                        key: const Key('nearbyPostError'),
                        style: const TextStyle(color: HuntrColors.coral)),
                  ),
                const SizedBox(height: 14),

                // ---- tags (optional) ----
                Material(
                  color: HuntrColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: HuntrColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('nearbyTags'),
                    onTap: _pickTags,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
                      child: Row(children: [
                        Text('#',
                            style: TextStyle(
                                color: HuntrColors.orange,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1)),
                        const SizedBox(width: 12),
                        if (_tagIds.isEmpty)
                          const Expanded(
                            child: Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: 'Tags',
                                  style: TextStyle(fontSize: 14.5)),
                              TextSpan(
                                  text: ' (optional)',
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      color: HuntrColors.muted)),
                            ])),
                          )
                        else ...[
                          const Text('Tags', style: TextStyle(fontSize: 14.5)),
                          const SizedBox(width: 8),
                          Container(
                            key: const Key('nearbyTagsCount'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: HuntrColors.orange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${_tagIds.length}',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_tagNames.join(', '),
                                key: const Key('nearbyTagsSummary'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: HuntrColors.muted, fontSize: 13.5)),
                          ),
                        ],
                        const Icon(Icons.chevron_right_rounded,
                            color: HuntrColors.muted),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- how far it reaches ----
                Material(
                  color: HuntrColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: HuntrColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('nearbyRadius'),
                    onTap: _pickRadius,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
                      child: Row(children: [
                        Icon(Icons.location_on_rounded,
                            color: HuntrColors.orange),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Broadcast to people nearby',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5)),
                        ),
                        const SizedBox(width: 8),
                        Text('Within ${nearbyRadiusLabel(_radiusM)}',
                            key: const Key('nearbyRadiusLabel'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const Icon(Icons.expand_more_rounded,
                            color: HuntrColors.muted),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(color: HuntrColors.border, height: 1),
                const SizedBox(height: 18),

                // ---- my threads ----
                const Text('My posts',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (mine == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (mine.isEmpty)
                  const Padding(
                    key: Key('nearbyNoMine'),
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                        "Your threads will show here. They're up for 7 days.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: HuntrColors.muted)),
                  )
                else ...[
                  for (final post in mine)
                    _MyPost(
                      key: ValueKey('nearbyMine-${post.id}'),
                      post: post,
                      now: now,
                      onOpen: () => _open(post),
                      onAction: (action) => _act(post, action),
                    ),
                  if (_next != null)
                    LoadMoreRow(onVisible: () => _loadMine(more: true)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of my threads: its random name and animal on that thread, how long
/// ago, what I wrote, and its hearts and comments.
class _MyPost extends StatelessWidget {
  const _MyPost({
    super.key,
    required this.post,
    required this.now,
    required this.onOpen,
    required this.onAction,
  });

  final NearbyPost post;
  final DateTime now;
  final VoidCallback onOpen;
  final ValueChanged<NearbyAction> onAction;

  @override
  Widget build(BuildContext context) {
    final ago = timeLabel(post.createdAt, now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 4, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NearbyAvatar(animal: post.author.avatar, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(post.author.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15.5, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Text(ago == 'now' ? 'just now' : '$ago ago',
                            style: const TextStyle(
                                color: HuntrColors.muted, fontSize: 13)),
                      ]),
                      const SizedBox(height: 6),
                      Text(post.body,
                          style: const TextStyle(fontSize: 15.5, height: 1.4)),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.favorite_border_rounded,
                            size: 20, color: HuntrColors.muted),
                        const SizedBox(width: 6),
                        Text('${post.likeCount}',
                            style: const TextStyle(color: HuntrColors.muted)),
                        const SizedBox(width: 26),
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 19, color: HuntrColors.muted),
                        const SizedBox(width: 6),
                        Text('${post.commentCount}',
                            style: const TextStyle(color: HuntrColors.muted)),
                      ]),
                    ]),
              ),
              NearbyMenu(mine: true, onSelected: onAction),
            ]),
          ),
        ),
      ),
    );
  }
}
