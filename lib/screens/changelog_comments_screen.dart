import 'package:flutter/material.dart';

import '../services/changelog_service.dart';
import '../services/huntr_backend.dart';
import '../services/nearby_service.dart' show nearbyAgo;
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/emoticons.dart';
import '../widgets/me/section_states.dart';
import '../widgets/nearby/nearby_post_card.dart'
    show
        HuntrPostAvatar,
        NearbyAction,
        NearbyAvatar,
        NearbyHeart,
        NearbyMenu,
        askReportReason;

/// The comments on a What's new entry, as in Threads: newest first, each
/// one's replies under it; mine (and my replies) under my anonymous name;
/// HUNTR's as HUNTR. Heart, reply, delete mine, report others'. Pops with
/// how many there are now (for the entry's count).
class ChangelogCommentsScreen extends StatefulWidget {
  const ChangelogCommentsScreen({super.key, required this.entry});

  final ChangelogEntry entry;

  @override
  State<ChangelogCommentsScreen> createState() =>
      _ChangelogCommentsScreenState();
}

class _ChangelogCommentsScreenState extends State<ChangelogCommentsScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  List<ChangelogComment>? _comments;
  late int _count = widget.entry.commentCount;
  String? _error;
  ChangelogComment? _replyTo;
  bool _sending = false;

  ChangelogService? get _service => ServicesScope.changelogOf(context);
  String? get _token => AppScope.read(context).sessionToken;

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

  void _show(ChangelogDiscussion discussion) => setState(() {
        _comments = discussion.comments;
        _count = discussion.count;
        _error = null;
      });

  Future<void> _load() async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    try {
      _show(await service.comments(token, widget.entry.id));
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    }
  }

  Future<void> _send() async {
    final service = _service;
    final token = _token;
    final text = _input.text.trim();
    if (service == null || token == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final after = await service.comment(token, widget.entry.id, text,
          parentId: _replyTo?.id);
      if (!mounted) return;
      _input.clear();
      _replyTo = null;
      _show(after);
      FocusScope.of(context).unfocus();
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "Your comment didn't go through.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reply(ChangelogComment comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  Future<void> _like(ChangelogComment comment) async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    try {
      await service.like(token, comment.id, !comment.liked);
      await _load();
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  Future<void> _act(NearbyAction action, ChangelogComment comment) async {
    final service = _service;
    final token = _token;
    if (service == null || token == null) return;
    try {
      if (action == NearbyAction.delete) {
        if (!await _confirmDelete()) return;
        await service.delete(token, comment.id);
      } else if (action == NearbyAction.report) {
        final reason = await askReportReason(context);
        if (reason == null) return;
        await service.report(token, comment.id, reason);
        _say("Thanks. It's reported, and you won't see it anymore.");
      }
      await _load();
    } catch (error) {
      _say(error is BackendException
          ? error.message
          : "That didn't go through.");
    }
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text('Delete this comment? Its replies go with it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            TextButton(
                key: const Key('changelogConfirmDelete'),
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

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final now = DateTime.now();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_count);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Comments')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              Expanded(
                child: RefreshIndicator(
                  color: HuntrColors.orange,
                  onRefresh: _load,
                  child: ListView(
                    key: const Key('changelogComments'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      Text(widget.entry.title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          [
                            if (widget.entry.version != null)
                              widget.entry.version!,
                            '$_count ${_count == 1 ? 'comment' : 'comments'}',
                          ].join('  ·  '),
                          style: const TextStyle(color: HuntrColors.muted)),
                      const SizedBox(height: 16),
                      if (comments == null && _error != null)
                        LoadFailedCard(
                            title: "Couldn't load the comments",
                            message: _error!,
                            onRetry: _load)
                      else if (comments == null)
                        const LoadingRows(count: 3, height: 70)
                      else if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                              'No comments yet. Tell us what you think.',
                              key: Key('changelogNoComments'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: HuntrColors.muted)),
                        )
                      else
                        for (final comment in comments) ...[
                          _CommentTile(
                            comment: comment,
                            now: now,
                            onReply: () => _reply(comment),
                            onLike: () => _like(comment),
                            onAction: (a) => _act(a, comment),
                          ),
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
                                    onLike: () => _like(reply),
                                    onAction: (a) => _act(a, reply),
                                  ),
                                ),
                              ),
                            ),
                        ],
                    ],
                  ),
                ),
              ),

              // ---- writing a comment ----
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
                            child: Text(
                                'Replying to ${to.official ? 'HUNTR' : to.author.name}',
                                key: const Key('changelogReplyingTo'),
                                style:
                                    const TextStyle(color: HuntrColors.muted)),
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
                          key: const Key('changelogCommentInput'),
                          controller: _input,
                          focusNode: _inputFocus,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: ChangelogService.commentMaxLength,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: const [EmoticonFormatter()],
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
                        key: const Key('changelogSendComment'),
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

/// One comment (or reply): who (an anonymous name, or HUNTR) and when, what
/// they said, its hearts, Reply, and the menu (Delete mine, Report others').
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.now,
    required this.onReply,
    required this.onLike,
    required this.onAction,
    this.small = false,
  });

  final ChangelogComment comment;
  final DateTime now;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final ValueChanged<NearbyAction> onAction;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 34.0 : 40.0;
    return Padding(
      key: Key('changelogComment-${comment.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        comment.official
            ? HuntrPostAvatar(size: size)
            : NearbyAvatar(
                animal: comment.author.avatar, size: size, mine: comment.mine),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: comment.official ? 'HUNTR' : comment.author.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (comment.official)
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.verified_rounded,
                          size: 15, color: HuntrColors.active),
                    ),
                  ),
                TextSpan(
                    text:
                        '  ·  ${comment.mine ? 'You · ' : ''}${nearbyAgo(comment.createdAt, now)}',
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
                  key: Key('changelogCommentLike-${comment.id}'),
                  count: comment.likeCount,
                  liked: comment.liked,
                  onTap: onLike,
                  size: 18),
              const SizedBox(width: 8),
              TextButton(
                key: Key('changelogReply-${comment.id}'),
                onPressed: onReply,
                style: TextButton.styleFrom(
                    foregroundColor: HuntrColors.muted,
                    visualDensity: VisualDensity.compact),
                child: const Text('Reply'),
              ),
            ]),
          ]),
        ),
        // HUNTR's can't be deleted or reported here
        if (!comment.official)
          NearbyMenu(mine: comment.mine, onSelected: onAction),
      ]),
    );
  }
}
