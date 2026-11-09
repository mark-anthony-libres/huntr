import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../flows/chat_attachments.dart' show ChatMediaPicker;
import '../services/huntr_backend.dart';
import '../services/nearby_service.dart';
import '../services/nearby_uploads.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/chat/picked_video_io.dart'
    if (dart.library.js_interop) '../widgets/chat/picked_video_web.dart';
import '../widgets/load_more_row.dart';
import '../widgets/nearby/nearby_media.dart' show NearbyMediaGrid;
import '../widgets/nearby/nearby_post_card.dart';
import '../widgets/nearby/nearby_tags.dart';
import 'chats_screen.dart' show timeLabel;
import 'nearby_post_screen.dart';

/// New thread: what's on my mind (up to [NearbyService.maxLength]
/// characters), one photo or video (optional; verified members), and how
/// far it reaches, then Post - it goes up under a random name and animal,
/// for 7 days (a verified member's, until it's deleted). A chosen photo or video starts
/// uploading at once (app-wide, [NearbyUploads]), and Post doesn't wait for
/// it: the thread shows how it's going. Below, my live threads (open one,
/// or delete it). Pops with the new thread once it's up.
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

  /// The photo or video chosen for it: its id once it's written on the
  /// backend (its file is sent from then on), and (while that's asked)
  /// [_choosing]; its picture from this device; why the last one couldn't
  /// be added.
  int? _mediaId;
  bool _choosing = false;
  Uint8List? _localPhoto;
  String? _localVideoPath;
  bool _pickedVideo = false;
  String? _mediaError;

  /// Counts picks: a Remove or Replace makes one still being written stale.
  int _pick = 0;

  /// Where the chosen one is uploading, and as whom: it's removed if the
  /// thread isn't posted.
  NearbyUploads? _uploads;
  String? _token;
  bool _posted = false;

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
    // closed without posting: the chosen one goes
    if (!_posted) _discardChosen();
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
      _text.text.length <= NearbyService.maxLength &&
      !_choosing;

  /// One photo or video from the library: checked for size here (and by
  /// the backend), shown from this device, and uploaded from now on.
  /// Replaces one chosen before.
  Future<void> _pickMedia() async {
    final uploads = ServicesScope.nearbyUploadsOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (uploads == null || token == null) return;
    final file = await ChatMediaPicker.instance.pickMedia();
    if (file == null || !mounted) return;
    if (await file.length() > NearbyService.maxUploadBytes) {
      if (mounted) {
        setState(() =>
            _mediaError = 'The file is too large. The maximum is 100 MB.');
      }
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final name = file.name.toLowerCase();
    final video = (file.mimeType ?? '').startsWith('video/') ||
        const ['.mp4', '.mov', '.webm', '.m4v']
            .any((extension) => name.endsWith(extension));
    final pick = ++_pick;
    _discardChosen();
    setState(() {
      _choosing = true;
      _pickedVideo = video;
      _localPhoto = video ? null : bytes;
      _localVideoPath = video ? file.path : null;
      _mediaError = null;
    });
    try {
      final media = await uploads.choose(token,
          bytes: bytes,
          // a file with no name would be sent as a plain field, not a file
          filename: file.name.isNotEmpty
              ? file.name
              : (video ? 'video.mp4' : 'photo.jpg'),
          isVideo: video);
      _uploads = uploads;
      _token = token;
      if (!mounted || pick != _pick) {
        unawaited(uploads.remove(token, media.id));
        return;
      }
      setState(() {
        _mediaId = media.id;
        _choosing = false;
      });
    } on SessionRejectedException {
      if (mounted) app.endSession();
    } catch (error) {
      if (!mounted || pick != _pick) return;
      _clearChosen(error is BackendException
          ? error.message
          : "It couldn't be added. Check your connection and try again.");
    }
  }

  /// A video longer than the backend takes is refused here already (when
  /// its length can be read on this device).
  void _checkVideoLength(Duration length) {
    if (length <= NearbyService.maxVideoLength) return;
    _pick++;
    _discardChosen();
    _clearChosen('The video is too long. The maximum is '
        '${NearbyService.maxVideoLength.inMinutes} minutes.');
  }

  void _removeMedia() {
    _pick++;
    _discardChosen();
    _clearChosen(null);
  }

  void _retryMedia() {
    final id = _mediaId, token = _token;
    if (id != null && token != null) _uploads?.retry(token, id);
  }

  /// The chosen one stops uploading and goes on the backend - just after
  /// this, as it may be while the screen closes (when nothing on screen may
  /// change).
  void _discardChosen() {
    final id = _mediaId, token = _token, uploads = _uploads;
    _mediaId = null;
    if (id != null && token != null && uploads != null) {
      scheduleMicrotask(() => uploads.remove(token, id));
    }
  }

  void _clearChosen(String? error) => setState(() {
        _mediaId = null;
        _choosing = false;
        _localPhoto = null;
        _localVideoPath = null;
        _mediaError = error;
      });

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
          body: _text.text,
          radiusM: _radiusM,
          tagIds: _tagIds.toList(),
          mediaId: _mediaId);
      // its photo or video keeps uploading: the thread shows how it's going
      _posted = true;
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
    // only verified members add a photo or video (the backend says so too)
    final verified = AppScope.of(context).myVerified;
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
                const SizedBox(height: 12),

                // ---- one photo or video (optional; verified members) ----
                if (!verified)
                  const Padding(
                    key: Key('nearbyMediaVerifiedOnly'),
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                        'Your thread stays up for 7 days. Verified members '
                        'can add a photo or video, and their threads stay up.',
                        style:
                            TextStyle(color: HuntrColors.muted, fontSize: 13)),
                  )
                else
                  _Attachment(
                    mediaId: _mediaId,
                    choosing: _choosing,
                    localPhoto: _localPhoto,
                    localVideoPath: _localVideoPath,
                    video: _pickedVideo,
                    onPick: _posting ? null : _pickMedia,
                    onRemove: _posting ? null : _removeMedia,
                    onRetry: _retryMedia,
                    onVideoLength: _checkVideoLength,
                  ),
                if (_mediaError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_mediaError!,
                        key: const Key('nearbyMediaError'),
                        style: const TextStyle(color: HuntrColors.coral)),
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
                    child: Text('Your threads will show here.',
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
/// ago, what I wrote, its photo or video, and its hearts and comments.
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
              NearbyAvatar(
                  animal: post.author.avatar, size: 52, mine: post.mine),
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
                      if (post.body.isNotEmpty)
                        Text(post.body,
                            style:
                                const TextStyle(fontSize: 15.5, height: 1.4)),
                      // its photo or video (or how its upload is going)
                      if (post.media.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                              top: post.body.isEmpty ? 0 : 10, right: 12),
                          child: NearbyMediaGrid(
                              key: Key('nearbyMineMedia-${post.id}'),
                              media: post.media),
                        ),
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

/// The thread's photo or video: "Add photo or video" until one is chosen;
/// then its picture from this device (a photo, or a video's first frame),
/// how its upload is going, and Replace or Remove (Try again when it
/// failed). Only one: no way to add a second.
class _Attachment extends StatelessWidget {
  const _Attachment({
    required this.mediaId,
    required this.choosing,
    required this.localPhoto,
    required this.localVideoPath,
    required this.video,
    required this.onPick,
    required this.onRemove,
    required this.onRetry,
    required this.onVideoLength,
  });

  final int? mediaId;
  final bool choosing;
  final Uint8List? localPhoto;
  final String? localVideoPath;
  final bool video;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;
  final VoidCallback onRetry;
  final ValueChanged<Duration> onVideoLength;

  @override
  Widget build(BuildContext context) {
    if (mediaId == null && !choosing) {
      return OutlinedButton.icon(
        key: const Key('nearbyAddMedia'),
        onPressed: onPick,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: const BorderSide(color: HuntrColors.border),
        ),
        icon:
            Icon(Icons.add_photo_alternate_outlined, color: HuntrColors.orange),
        label: const Text('Add photo or video'),
      );
    }
    final Widget picture;
    if (localPhoto != null) {
      picture = Image.memory(localPhoto!, fit: BoxFit.cover);
    } else if (localVideoPath != null) {
      picture = _LocalVideoFrame(
          key: ValueKey(localVideoPath),
          path: localVideoPath!,
          onLength: onVideoLength);
    } else {
      picture = const ColoredBox(
          color: HuntrColors.surfaceHigh,
          child: Center(
              child: Icon(Icons.videocam_outlined,
                  size: 40, color: HuntrColors.muted)));
    }
    final uploads = ServicesScope.nearbyUploadsOf(context);
    return Container(
      key: const Key('nearbyMediaPicked'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HuntrColors.border),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(dimension: 84, child: picture),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video ? 'Video' : 'Photo',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (uploads != null)
                ListenableBuilder(
                  listenable: uploads,
                  builder: (context, _) => _UploadLine(
                      upload: mediaId == null ? null : uploads.of(mediaId!)),
                ),
              const SizedBox(height: 4),
              // on a narrow screen Try again goes under the others
              Wrap(children: [
                TextButton(
                  key: const Key('nearbyReplaceMedia'),
                  onPressed: onPick,
                  child: const Text('Replace'),
                ),
                TextButton(
                  key: const Key('nearbyRemoveMedia'),
                  onPressed: onRemove,
                  child: const Text('Remove',
                      style: TextStyle(color: HuntrColors.coral)),
                ),
                if (uploads != null && mediaId != null)
                  ListenableBuilder(
                    listenable: uploads,
                    builder: (context, _) => uploads.of(mediaId!)?.error == null
                        ? const SizedBox.shrink()
                        : TextButton(
                            key: const Key('nearbyRetryMedia'),
                            onPressed: onRetry,
                            child: const Text('Try again'),
                          ),
                  ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// How its upload is going: "Uploading 40%" with a bar, "Uploaded", or why
/// it failed.
class _UploadLine extends StatelessWidget {
  const _UploadLine({required this.upload});

  /// Null while it's being written on the backend (nothing sent yet).
  final NearbyUpload? upload;

  @override
  Widget build(BuildContext context) {
    final upload = this.upload;
    if (upload?.error case final error?) {
      return Text(error,
          key: const Key('nearbyMediaUploadError'),
          style: const TextStyle(color: HuntrColors.coral, fontSize: 13));
    }
    if (upload?.stored != null) {
      return const Text('Uploaded',
          key: Key('nearbyMediaUploaded'),
          style: TextStyle(color: HuntrColors.muted, fontSize: 13));
    }
    final sent = upload?.sent ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Uploading ${(sent * 100).floor()}%',
          key: const Key('nearbyMediaProgress'),
          style: const TextStyle(color: HuntrColors.muted, fontSize: 13)),
      const SizedBox(height: 6),
      LinearProgressIndicator(
          value: sent, minHeight: 4, borderRadius: BorderRadius.circular(4)),
    ]);
  }
}

/// A video chosen on this device: its first frame, and (once read) how
/// long it is. Some can't be read here (a format the browser can't play):
/// a video mark, and the backend checks it.
class _LocalVideoFrame extends StatefulWidget {
  const _LocalVideoFrame(
      {super.key, required this.path, required this.onLength});

  final String path;
  final ValueChanged<Duration> onLength;

  @override
  State<_LocalVideoFrame> createState() => _LocalVideoFrameState();
}

class _LocalVideoFrameState extends State<_LocalVideoFrame> {
  late final VideoPlayerController _player = pickedVideoController(widget.path);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      widget.onLength(_player.value.duration);
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _player.value.size;
    return ColoredBox(
      color: HuntrColors.surfaceHigh,
      child: Stack(fit: StackFit.expand, children: [
        if (!_failed && _player.value.isInitialized && !size.isEmpty)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(_player)),
          ),
        const Center(
            child: Icon(Icons.play_circle_fill_rounded,
                color: Colors.white70, size: 30)),
      ]),
    );
  }
}
