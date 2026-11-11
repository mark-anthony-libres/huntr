import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';
import '../widgets/network_photo.dart';
import '../widgets/photos/viewer_controls.dart';
import '../widgets/photos/zoomable.dart';
import '../widgets/reply_bar.dart';
import '../widgets/stories/reaction_burst.dart';

/// Someone's profile photos full screen (pinch to zoom, swipe for the next),
/// and, like a story, a reply box with quick reactions: what's sent goes to
/// our direct chat as a reply to that photo.
class PersonPhotoViewerScreen extends StatefulWidget {
  const PersonPhotoViewerScreen(
      {super.key, required this.profile, this.initialIndex = 0});

  final Profile profile;
  final int initialIndex;

  /// The quick reactions (the same as under a story).
  static const reactions = ['❤️', '😍', '👍'];

  @override
  State<PersonPhotoViewerScreen> createState() =>
      _PersonPhotoViewerScreenState();
}

class _PersonPhotoViewerScreenState extends State<PersonPhotoViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  bool _sending = false;
  bool _zoomed = false;

  /// The reaction playing big over the photo (a new [_bursts] replays it).
  String? _burst;
  int _bursts = 0;

  /// At most one reaction this often: a burst of taps sends one.
  Timer? _reactionPause;

  List<String> get _urls => widget.profile.photoUrls;

  /// Replies need the photo's id (the profile as opened, not from a list)
  /// and a chat to send them to.
  int? get _photoId => widget.profile.photoIds.length == _urls.length &&
          _index < widget.profile.photoIds.length
      ? widget.profile.photoIds[_index]
      : null;

  @override
  void dispose() {
    _pages.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    _reactionPause?.cancel();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 2),
          // above the reply box, which stays usable
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 84)));
  }

  Future<void> _send(String body) async {
    final photoId = _photoId;
    final messaging = MessagingScope.read(context);
    final text = body.trim();
    if (photoId == null || messaging == null || text.isEmpty || _sending) {
      return;
    }
    final reaction = PersonPhotoViewerScreen.reactions.contains(text);
    if (reaction) {
      if (_reactionPause?.isActive ?? false) return;
      _reactionPause = Timer(const Duration(seconds: 2), () {});
      setState(() {
        _burst = text;
        _bursts++;
      });
    } else {
      _reply.clear();
      _replyFocus.unfocus();
    }
    final name = widget.profile.shortName;
    _sending = true;
    try {
      await messaging.replyToPhoto(photoId, text);
      if (mounted) {
        _say(reaction ? '$text sent to $name' : 'Reply sent to $name');
      }
    } catch (error) {
      if (mounted) {
        _say(error is BackendException ? error.message : "That didn't send.");
      }
    } finally {
      _sending = false;
    }
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, _urls.length - 1);
    if (next != _index) {
      _pages.animateToPage(next,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _urls.length;
    final canReply = _photoId != null && MessagingScope.read(context) != null;
    return Scaffold(
      key: const Key('photoViewer'),
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          // ---- top: who, which photo, close ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  count > 1
                      ? '${widget.profile.shortName} · ${_index + 1} / $count'
                      : widget.profile.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
              IconButton(
                key: const Key('photoViewerClose'),
                tooltip: 'Close',
                color: Colors.white,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),

          // ---- the photos ----
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              SwipeAnyDevice(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: count,
                  // zoomed in: a swipe moves the photo, not to the next
                  physics:
                      _zoomed ? const NeverScrollableScrollPhysics() : null,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (_, i) => Zoomable(
                    onZoomed: (zoomed) => setState(() => _zoomed = zoomed),
                    child: NetworkPhoto(_urls[i], fit: BoxFit.contain),
                  ),
                ),
              ),
              if (count > 1 && _index > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ArrowButton(
                      key: const Key('photoViewerPrevious'),
                      icon: Icons.chevron_left,
                      tooltip: 'Previous photo',
                      onPressed: () => _go(-1)),
                ),
              if (count > 1 && _index < count - 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: ArrowButton(
                      key: const Key('photoViewerNext'),
                      icon: Icons.chevron_right,
                      tooltip: 'Next photo',
                      onPressed: () => _go(1)),
                ),
              if (_burst case final emoji?)
                IgnorePointer(
                  child: Center(
                    child: ReactionBurst(
                      key: ValueKey(_bursts),
                      emoji: emoji,
                      onDone: () => setState(() => _burst = null),
                    ),
                  ),
                ),
            ]),
          ),

          // ---- bottom: reply and react ----
          if (canReply)
            Padding(
              padding: const EdgeInsets.all(12),
              child: ReplyBar(
                  controller: _reply,
                  focusNode: _replyFocus,
                  reactions: PersonPhotoViewerScreen.reactions,
                  onSend: _send,
                  keyPrefix: 'photo'),
            ),
        ]),
      ),
    );
  }
}
