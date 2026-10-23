import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/nearby_service.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/me/section_states.dart';
import '../widgets/nearby/nearby_post_card.dart';

/// A Nearby post and its discussion: comments (newest first) with their
/// replies threaded under them, each by a random name kept for this post.
/// Pops with the post as it is now (for the feed's counts), or null when
/// it's gone (deleted, reported, out of reach).
class NearbyPostScreen extends StatefulWidget {
  const NearbyPostScreen({super.key, required this.post});

  final NearbyPost post;

  @override
  State<NearbyPostScreen> createState() => _NearbyPostScreenState();
}

class _NearbyPostScreenState extends State<NearbyPostScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  late NearbyPost _post = widget.post;
  List<NearbyComment>? _comments;
  String? _error;
  bool _gone = false;
  bool _sending = false;

  /// Replying to this comment (null: a new comment).
  NearbyComment? _replyTo;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  NearbyService? get _service => ServicesScope.nearbyOf(context);
  String? get _token => AppScope.read(context).sessionToken;

  void _show(NearbyDiscussion discussion) => setState(() {
        _post = discussion.post;
        _comments = discussion.comments;
        _error = null;
      });

  Future<void> _load() async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    try {
      _show(await service.discussion(token, _post.id));
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } on NearbyNoLocationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on BackendException catch (error) {
      if (!mounted) return;
      // gone (deleted, expired, out of reach) or another problem
      setState(() {
        _gone = error.message.contains("isn't available");
        _error = error.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Check your connection and try again.');
      }
    }
  }

  Future<void> _send() async {
    final service = _service;
    final token = _token;
    final body = _input.text.trim();
    if (service == null || token == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final discussion = await service.comment(token, _post.id,
          body: body, parentId: _replyTo?.id);
      if (!mounted) return;
      _input.clear();
      _replyTo = null;
      _show(discussion);
      _inputFocus.unfocus();
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "Your comment didn't go through. Try again.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reply(NearbyComment comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  Future<void> _likePost() async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    final before = _post;
    setState(() => _post = before.copyWith(
        liked: !before.liked,
        likeCount: before.likeCount + (before.liked ? -1 : 1)));
    try {
      final r = await service.like(token, before.id, like: !before.liked);
      if (mounted) {
        setState(
            () => _post = before.copyWith(likeCount: r.count, liked: r.liked));
      }
    } catch (error) {
      if (mounted) setState(() => _post = before);
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  Future<void> _likeComment(NearbyComment comment) async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    try {
      await service.like(token, _post.id,
          commentId: comment.id, like: !comment.liked);
      await _load();
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  Future<void> _act(NearbyAction action, {NearbyComment? comment}) async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    try {
      if (action == NearbyAction.delete) {
        if (!await _confirm(comment == null
            ? 'Delete this post? Its comments go with it.'
            : 'Delete this comment? Its replies go with it.')) {
          return;
        }
        await service.delete(token,
            postId: comment == null ? _post.id : null, commentId: comment?.id);
      } else {
        final reason = await askReportReason(context);
        if (reason == null) return;
        await service.report(token, _post.id,
            commentId: comment?.id, reason: reason);
        _say("Thanks. It's reported, and you won't see it anymore.");
      }
      if (!mounted) return;
      if (comment == null) {
        Navigator.of(context).pop(); // the post is gone for me
      } else {
        await _load();
      }
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  Future<bool> _confirm(String question) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(question),
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

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int get _commentTotal => (_comments ?? const <NearbyComment>[])
      .fold(0, (sum, c) => sum + 1 + c.replies.length);

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final now = DateTime.now();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // back to the feed with the latest counts (or nothing: it's gone)
        Navigator.of(context).pop(_gone
            ? null
            : _post.copyWith(
                commentCount: comments == null ? null : _commentTotal));
      },
      child: Scaffold(
        appBar: AppBar(),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              Expanded(
                child: ListView(
                  key: const Key('nearbyDiscussion'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (_gone)
                      EmptyStateCard(
                        icon: Icons.visibility_off_outlined,
                        title: 'Not available',
                        message: _error ?? "This post isn't available anymore.",
                      )
                    else ...[
                      NearbyPostCard(
                        post: _post,
                        now: now,
                        large: true,
                        onLike: _likePost,
                        onAction: (action) => _act(action),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Text('Comments',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Text(
                            '${comments == null ? _post.commentCount : _commentTotal}',
                            style: const TextStyle(
                                color: HuntrColors.muted, fontSize: 16)),
                        const Spacer(),
                        const Text('Newest',
                            style: TextStyle(color: HuntrColors.muted)),
                      ]),
                      const SizedBox(height: 12),
                      if (comments == null && _error != null)
                        LoadFailedCard(
                            title: "Couldn't load the comments",
                            message: _error!,
                            onRetry: _load)
                      else if (comments == null)
                        const LoadingRows(count: 3, height: 70)
                      else if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                              'No comments yet. Start the conversation.',
                              key: Key('nearbyNoComments'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: HuntrColors.muted)),
                        )
                      else
                        for (final comment in comments) ...[
                          _CommentTile(
                            comment: comment,
                            now: now,
                            onReply: () => _reply(comment),
                            onLike: () => _likeComment(comment),
                            onAction: (a) => _act(a, comment: comment),
                          ),
                          // its replies, threaded under it
                          for (final reply in comment.replies)
                            Padding(
                              padding: const EdgeInsets.only(left: 28),
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                    border: Border(
                                        left: BorderSide(
                                            color: HuntrColors.border,
                                            width: 2))),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: _CommentTile(
                                    comment: reply,
                                    now: now,
                                    small: true,
                                    onReply: () => _reply(comment),
                                    onLike: () => _likeComment(reply),
                                    onAction: (a) => _act(a, comment: reply),
                                  ),
                                ),
                              ),
                            ),
                        ],
                    ],
                  ],
                ),
              ),

              // ---- writing a comment ----
              if (!_gone)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_replyTo case final to?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            const Icon(Icons.reply_rounded,
                                size: 16, color: HuntrColors.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Replying to ${to.author.name}',
                                  key: const Key('nearbyReplyingTo'),
                                  style: const TextStyle(
                                      color: HuntrColors.muted)),
                            ),
                            IconButton(
                              tooltip: 'Cancel reply',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _replyTo = null),
                            ),
                          ]),
                        ),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            key: const Key('nearbyCommentInput'),
                            controller: _input,
                            focusNode: _inputFocus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: NearbyService.maxLength,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: _replyTo == null
                                  ? 'Add a comment…'
                                  : 'Write a reply…',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const Key('nearbySendComment'),
                          tooltip: 'Send',
                          style: IconButton.styleFrom(
                              backgroundColor: HuntrColors.orange,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(48, 48)),
                          onPressed: _input.text.trim().isEmpty || _sending
                              ? null
                              : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One comment (or reply): who, how far and when, what they said, its
/// hearts and Reply.
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.now,
    required this.onReply,
    required this.onLike,
    required this.onAction,
    this.small = false,
  });

  final NearbyComment comment;
  final DateTime now;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final ValueChanged<NearbyAction> onAction;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('nearbyComment-${comment.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NearbyAvatar(animal: comment.author.avatar, size: small ? 34 : 40),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: comment.author.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (comment.byAuthor)
                  TextSpan(
                      text: '  · Author',
                      style: TextStyle(
                          color: HuntrColors.orange,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                TextSpan(
                    text:
                        '  ·  ${nearbyMeta(distanceM: comment.distanceM, at: comment.createdAt, now: now, mine: comment.mine)}',
                    style: const TextStyle(
                        color: HuntrColors.muted, fontSize: 12.5)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(comment.body,
                style: const TextStyle(fontSize: 15, height: 1.35)),
            Row(children: [
              NearbyHeart(
                  key: Key('nearbyCommentLike-${comment.id}'),
                  count: comment.likeCount,
                  liked: comment.liked,
                  onTap: onLike,
                  size: 18),
              const SizedBox(width: 8),
              TextButton(
                key: Key('nearbyReply-${comment.id}'),
                onPressed: onReply,
                style: TextButton.styleFrom(
                    foregroundColor: HuntrColors.muted,
                    visualDensity: VisualDensity.compact),
                child: const Text('Reply'),
              ),
            ]),
          ]),
        ),
        NearbyMenu(mine: comment.mine, onSelected: onAction),
      ]),
    );
  }
}
