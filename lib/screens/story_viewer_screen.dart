import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:video_player/video_player.dart';

import '../flows/open_person_profile.dart';
import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/story_cache/story_video_cache.dart';
import '../services/story_service.dart';
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/stories/reaction_burst.dart';
import '../widgets/stories/story_round_button.dart';

/// Stories, full screen: each person's in turn, then the next person's. Tap
/// the right side for the next story, the left for the one before, hold to
/// pause. Others' stories take a reply or a quick reaction (it goes to our
/// direct chat); my own show who watched and can be deleted. Nothing can be
/// saved, downloaded or shared, for privacy.
class StoryViewerScreen extends StatefulWidget {
  /// The stories of [people], after mine when [me] is given; [start] counts
  /// in that order (with [me], 0 is mine).
  const StoryViewerScreen(
      {super.key,
      required this.service,
      required List<Profile> this.people,
      this.me,
      this.start = 0,
      this.startStoryId});

  /// Only my own stories.
  const StoryViewerScreen.mine(
      {super.key,
      required this.service,
      required Profile this.me,
      this.startStoryId})
      : people = null,
        start = 0;

  final StoryService service;
  final List<Profile>? people;
  final int start;
  final Profile? me;

  /// The first person's story to begin with (a thumbnail tapped); otherwise
  /// their first I haven't seen.
  final int? startStoryId;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late int _person = widget.start;
  bool _startUsed = false;
  List<Story>? _stories;
  int _index = 0;
  VideoPlayerController? _player;
  String? _error;
  final Set<int> _watched = {};
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  String? _toast;
  bool _toastIsError = false;
  Timer? _toastTimer;

  /// The quick reactions under someone's story.
  static const _reactions = ['❤️', '😍', '👍'];

  /// At most one reaction this often: a burst of taps sends one.
  static const _reactionGap = Duration(seconds: 2);
  Timer? _reactionPause;

  /// The reaction playing big over the story (a new [_bursts] replays it).
  String? _burst;
  int _bursts = 0;

  /// Everyone whose stories this shows, in turn (me first, for my own).
  late final List<Profile> _everyone = [
    if (widget.me != null) widget.me!,
    ...?widget.people,
  ];

  Profile get _who => _everyone[_person];

  /// Watching my own stories (who saw them, delete) rather than someone's.
  bool get _isMine => widget.me != null && _person == 0;

  @override
  void initState() {
    super.initState();
    _replyFocus.addListener(() {
      // typing a reply pauses the story
      _replyFocus.hasFocus ? _player?.pause() : _player?.play();
    });
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    _toastTimer?.cancel();
    _reactionPause?.cancel();
    super.dispose();
  }

  String? get _token => AppScope.read(context).sessionToken;

  /// The current person's stories, starting at the first I haven't seen.
  Future<void> _load() async {
    final token = _token;
    final userId = _who.backendId;
    if (token == null || (!_isMine && userId == null)) return;
    setState(() {
      _stories = null;
      _error = null;
    });
    try {
      final stories = _isMine
          ? await widget.service.mine(token)
          : await widget.service.of(token, userId!);
      if (!mounted) return;
      if (stories.isEmpty) return _nextPerson();
      _watched.addAll(stories.where((s) => s.seen).map((s) => s.id));
      final firstNew = stories.indexWhere((s) => !s.seen);
      setState(() => _stories = stories);
      // the tapped story, the first time only (not on coming back)
      final chosen = _startUsed
          ? -1
          : stories.indexWhere((s) => s.id == widget.startStoryId);
      _startUsed = true;
      await _show(chosen >= 0
          ? chosen
          : _isMine || firstNew < 0
              ? 0
              : firstNew);
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : "Stories couldn't load. Check your connection.");
      }
    }
  }

  Future<void> _show(int index) async {
    final stories = _stories!;
    final story = stories[index];
    final previous = _player;
    setState(() {
      _index = index;
      _error = null;
      _player = null;
    });
    // the old one is released in the background: the next story never
    // waits for it
    unawaited(previous?.dispose());
    // from the device when it's there (downloaded and kept otherwise)
    final player = await StoryVideoCache.player(story);
    // moved on meanwhile (swiped, closed, another person's stories)
    if (!mounted ||
        !identical(_stories, stories) ||
        _index != index ||
        _player != null) {
      await player.dispose();
      return;
    }
    setState(() => _player = player);
    try {
      await player.initialize();
    } catch (error) {
      if (mounted && identical(_player, player)) {
        setState(() => _error = "This story couldn't play.");
      }
      return;
    }
    if (!mounted || !identical(_player, player)) return;
    player.addListener(() => _ended(player));
    if (!_replyFocus.hasFocus) await player.play();
    setState(() {});
    _markWatched(story);
    // the next one is ready by the time this one ends
    if (index + 1 < stories.length) {
      unawaited(StoryVideoCache.prefetch(stories[index + 1]));
    }
  }

  void _markWatched(Story story) {
    final token = _token;
    if (_isMine || token == null || !_watched.add(story.id)) return;
    widget.service.markViewed(token, story.id).catchError(
        (Object error) => debugPrint('Story view not recorded: $error'));
    final stories = _stories!;
    if (stories.every((s) => _watched.contains(s.id))) {
      // their ring in Explore turns grey
      AppScope.read(context).updateNearbyPerson(_who.copyWith(storySeen: true));
    }
  }

  /// The video that already ended (a player reports the end several times;
  /// moving on more than once skipped stories and closed the screen below).
  VideoPlayerController? _finished;

  void _ended(VideoPlayerController player) {
    final value = player.value;
    if (!identical(_player, player) ||
        identical(_finished, player) ||
        !value.isInitialized) {
      return;
    }
    final done = value.isCompleted ||
        (value.duration > Duration.zero &&
            value.position >= value.duration &&
            !value.isPlaying);
    if (!done) return;
    _finished = player;
    _next();
  }

  bool _leaving = false;

  /// Closes the viewer, once (never the screen below it).
  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pop();
  }

  void _next() {
    final stories = _stories;
    if (stories != null && _index + 1 < stories.length) {
      _show(_index + 1);
    } else {
      _nextPerson();
    }
  }

  /// Back a story, or to the previous person's.
  void _previous() {
    if (_index > 0) {
      _show(_index - 1);
    } else if (_hasPreviousPerson) {
      setState(() => _person--);
      _load();
    }
  }

  bool get _hasPreviousPerson => _person > 0;
  bool get _canGoBack => _index > 0 || _hasPreviousPerson;

  /// On to the next person with a story, or done.
  void _nextPerson() {
    if (_person + 1 < _everyone.length) {
      setState(() => _person++);
      _load();
    } else {
      _leave();
    }
  }

  void _say(String text, {bool error = false}) {
    _toastTimer?.cancel();
    setState(() {
      _toast = text;
      _toastIsError = error;
    });
    _toastTimer = Timer(const Duration(seconds: 2),
        () => mounted ? setState(() => _toast = null) : null);
  }

  /// A reply or a reaction, to our direct chat.
  Future<void> _send(String body) async {
    final story = _stories?[_index];
    final token = _token;
    final messaging = MessagingScope.read(context);
    final text = body.trim();
    if (story == null || token == null || messaging == null || text.isEmpty) {
      return;
    }
    final reaction = _reactions.contains(text);
    if (reaction) {
      if (_reactionPause?.isActive ?? false) return;
      _reactionPause = Timer(_reactionGap, () {});
      // shown at once; the reply being typed stays
      setState(() {
        _burst = text;
        _bursts++;
      });
    } else {
      _reply.clear();
      _replyFocus.unfocus();
    }
    final name = _who.shortName;
    try {
      if (reaction) {
        // kept with the story, for their Seen by (not a message)
        await widget.service.react(token, story.id, text);
        _say('$text sent to $name');
      } else {
        await widget.service.reply(token, story.id,
            body: text, clientId: messaging.newClientId());
        _say('Reply sent to $name');
        unawaited(messaging.refresh()); // the chat shows up in Chats
      }
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      _say(error is BackendException ? error.message : "That didn't send.",
          error: true);
    }
  }

  Future<void> _showViewers(Story story) async {
    final token = _token;
    if (token == null) return;
    _player?.pause();
    StoryViewer? opened;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => _ViewersSheet(
        load: () => widget.service.viewers(token, story.id),
        onOpen: (viewer) {
          Navigator.of(sheet).pop();
          opened = viewer;
        },
      ),
    );
    if (opened case final viewer? when mounted) {
      // their profile; the story waits until I'm back
      await openPersonProfile(
          context,
          Profile.nearby({
            'id': viewer.userId,
            'display_name': viewer.name,
            'photo_url': viewer.photoUrl,
          }));
    }
    if (mounted) _player?.play();
  }

  /// ⋯ on someone else's story.
  Future<void> _theirMenu() async {
    _player?.pause();
    final who = _who;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListTile(
          key: const Key('storyMenu-profile'),
          leading: const Icon(Icons.person_outline_rounded),
          title: Text("View ${who.shortName}'s profile"),
          onTap: () => Navigator.pop(context, 'profile'),
        ),
      ),
    );
    if (choice == 'profile' && mounted) await _openProfile(who);
    if (mounted) _player?.play();
  }

  /// Their profile (tapping their picture or name, or ⋯); the story waits
  /// until I'm back.
  Future<void> _openProfile([Profile? person]) async {
    final who = person ?? _who;
    _player?.pause();
    await openPersonProfile(context, who);
    if (mounted) _player?.play();
  }

  Future<void> _menu(Story story) async {
    _player?.pause();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('storyMenu-viewers'),
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Seen by'),
            trailing: Text('${story.viewCount ?? 0}',
                style: const TextStyle(color: HuntrColors.muted)),
            onTap: () => Navigator.pop(context, 'viewers'),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            key: const Key('storyMenu-delete'),
            leading: const Icon(Icons.delete_outline, color: HuntrColors.coral),
            title: const Text('Delete story',
                style: TextStyle(color: HuntrColors.coral)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'viewers':
        return _showViewers(story);
      case 'delete':
        return _delete(story);
    }
    _player?.play();
  }

  Future<void> _delete(Story story) async {
    final token = _token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this story?'),
            content: const Text('It disappears for everyone right away.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  key: const Key('confirmDeleteStory'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete',
                      style: TextStyle(color: HuntrColors.coral))),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      _player?.play();
      return;
    }
    try {
      await widget.service.delete(token, story.id);
    } catch (error) {
      _say("The story wasn't deleted. Please try again.", error: true);
      _player?.play();
      return;
    }
    if (!mounted) return;
    final left = [...?_stories]..removeAt(_index);
    if (left.isEmpty) {
      _leave();
      return;
    }
    setState(() => _stories = left);
    await _show(_index.clamp(0, left.length - 1));
  }

  /// Where the previous / next buttons go: the middle of the sides on a wide
  /// screen, the bottom corners on a phone (under the thumbs).
  /// A side button, halfway down.
  Widget _arrowAt({required bool left, required Widget child}) => Positioned(
        left: left ? 12 : null,
        right: left ? null : 12,
        top: 0,
        bottom: 0,
        child: Center(child: child),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final stories = _stories;
    final player = _player;
    final story = stories == null ? null : stories[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(children: [
                  // ---- the video (it never takes touches: in a browser a
                  // video element would swallow them) ----
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: const Color(0xFF111114),
                        child: Center(
                          child: _error != null
                              ? Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(_error!,
                                      textAlign: TextAlign.center,
                                      style:
                                          const TextStyle(color: Colors.white)))
                              : player != null && player.value.isInitialized
                                  ? FittedBox(
                                      fit: BoxFit.cover,
                                      clipBehavior: Clip.hardEdge,
                                      child: SizedBox(
                                          width: player.value.size.width,
                                          height: player.value.size.height,
                                          child: VideoPlayer(player)))
                                  : CircularProgressIndicator(
                                      color: HuntrColors.orange),
                        ),
                      ),
                    ),
                  ),
                  // ---- where taps go: over the video, under the buttons.
                  // In a browser the video is a page element that would
                  // take the taps; PointerInterceptor gives them to HUNTR
                  // (it does nothing in the apps) ----
                  Positioned.fill(
                    child: PointerInterceptor(
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          key: const Key('storyTapArea'),
                          behavior: HitTestBehavior.opaque,
                          // left third: back; the rest: next
                          onTapUp: (details) =>
                              details.localPosition.dx < box.maxWidth / 3
                                  ? _previous()
                                  : _next(),
                          onLongPressStart: (_) => player?.pause(),
                          onLongPressEnd: (_) => player?.play(),
                          // swipe left for the next, right for the one before
                          onHorizontalDragEnd: (details) {
                            final speed = details.primaryVelocity ?? 0;
                            if (speed < -250) _next();
                            if (speed > 250) _previous();
                          },
                        ),
                      ),
                    ),
                  ),
                  // a soft shade so the top stays readable
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 120,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x99000000), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ---- top: progress, who, close ----
                  Positioned(
                    left: 12,
                    right: 4,
                    top: 10,
                    child: Column(children: [
                      if (stories != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(children: [
                            for (var i = 0; i < stories.length; i++) ...[
                              if (i > 0) const SizedBox(width: 4),
                              Expanded(
                                  child: _Segment(
                                      player: i == _index ? player : null,
                                      done: i < _index)),
                            ],
                          ]),
                        ),
                      const SizedBox(height: 12),
                      Row(children: [
                        // picture, name, and when it was posted under it
                        // (someone's opens their profile); it takes the free
                        // space, so ⋯ and Close stay at the right
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              key: const Key('storyWho'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _isMine ? null : _openProfile,
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipOval(
                                      child: SizedBox(
                                          width: 42,
                                          height: 42,
                                          child: ProfileArt(
                                              profile: _who, fontSize: 16)),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                _isMine
                                                    ? 'Your Story'
                                                    : _who.shortName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    shadows: _readable)),
                                            if (story != null)
                                              Text(_ago(story.postedAt),
                                                  style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                      shadows: _readable)),
                                          ]),
                                    ),
                                  ]),
                            ),
                          ),
                        ),
                        if (story != null)
                          _HeaderIcon(
                            key: const Key('storyMenu'),
                            tooltip: 'More',
                            icon: Icons.more_horiz_rounded,
                            onPressed: () =>
                                _isMine ? _menu(story) : _theirMenu(),
                          ),
                        _HeaderIcon(
                          key: const Key('closeStory'),
                          tooltip: 'Close',
                          icon: Icons.close_rounded,
                          onPressed: _leave,
                        ),
                      ]),
                    ]),
                  ),

                  // ---- previous / next, on wide screens (a phone taps
                  // and swipes) ----
                  if (wide && _canGoBack)
                    _arrowAt(
                      left: true,
                      child: StoryRoundButton(
                        key: const Key('storyPrevious'),
                        tooltip: 'Previous',
                        icon: Icons.chevron_left_rounded,
                        size: 52,
                        onPressed: _previous,
                      ),
                    ),
                  if (wide)
                    _arrowAt(
                      left: false,
                      child: StoryRoundButton(
                        key: const Key('storyNext'),
                        tooltip: 'Next',
                        icon: Icons.chevron_right_rounded,
                        size: 52,
                        onPressed: _next,
                      ),
                    ),

                  if (_burst case final emoji?)
                    Positioned.fill(
                      child: Center(
                        child: ReactionBurst(
                          key: ValueKey(_bursts),
                          emoji: emoji,
                          onDone: () => setState(() => _burst = null),
                        ),
                      ),
                    ),
                  if (_toast case final toast?)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 20,
                      child: Center(
                        child: _Toast(
                            key: const Key('storyToast'),
                            text: toast,
                            error: _toastIsError),
                      ),
                    ),
                ]),
              ),
            ),
          ),

          // ---- bottom: reply and react, or my story's tools ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: _isMine
                ? (story == null
                    ? const SizedBox(height: 48)
                    : Row(children: [
                        TextButton.icon(
                          key: const Key('storySeenBy'),
                          onPressed: () => _showViewers(story),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          icon: const Icon(Icons.visibility_outlined),
                          label: Text('Seen by ${story.viewCount ?? 0}'),
                        ),
                      ]))
                : Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('storyReply'),
                        controller: _reply,
                        focusNode: _replyFocus,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Send a message…',
                          hintStyle: const TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: const BorderSide(color: Colors.white38),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide(color: HuntrColors.orange),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // typing: a send button (Enter sends too); otherwise the
                    // quick reactions
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _reply,
                      builder: (context, value, _) => value.text.trim().isEmpty
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              for (final emoji in _reactions)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: IconButton(
                                    key: Key('storyReact-$emoji'),
                                    tooltip: 'React $emoji',
                                    style: IconButton.styleFrom(
                                        minimumSize: const Size(48, 48)),
                                    onPressed: () => _send(emoji),
                                    icon: Text(emoji,
                                        style: const TextStyle(fontSize: 30)),
                                  ),
                                ),
                            ])
                          : Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: IconButton.filled(
                                key: const Key('storySend'),
                                tooltip: 'Send',
                                style: IconButton.styleFrom(
                                    backgroundColor: HuntrColors.orange,
                                    foregroundColor: Colors.black,
                                    minimumSize: const Size(48, 48)),
                                onPressed: () => _send(_reply.text),
                                icon: const Icon(Icons.send_rounded),
                              ),
                            ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// A soft shadow under text over the video, so it reads on any picture.
const _readable = [Shadow(color: Colors.black87, blurRadius: 6)];

/// ⋯ and Close at the top: plain white icons, shadowed so they show over
/// any video.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon(
      {super.key,
      required this.tooltip,
      required this.icon,
      required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 28, shadows: _readable),
      );
}

/// A short note over the story: orange when something went out, red when it
/// didn't. It pops in so it's noticed.
class _Toast extends StatelessWidget {
  const _Toast({super.key, required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
          decoration: BoxDecoration(
            gradient: error ? null : HuntrColors.accentGradient,
            color: error ? const Color(0xFFD64545) : null,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                  color: (error ? Colors.red : HuntrColors.orange)
                      .withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(error ? Icons.error_rounded : Icons.check_circle_rounded,
                color: error ? Colors.white : Colors.black, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: error ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
          ]),
        ),
      );
}

/// "Just now", "5m ago", "3h ago": how long ago it was posted.
String _ago(DateTime time) {
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  return '${elapsed.inHours}h ago';
}

/// One story's bar at the top: full once watched, filling while playing.
class _Segment extends StatelessWidget {
  const _Segment({required this.player, required this.done});

  final VideoPlayerController? player;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final current = player;
    Widget bar(double value) => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: Colors.white24,
            color: Colors.white,
          ),
        );
    if (current == null) return bar(done ? 1 : 0);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: current,
      builder: (_, value, __) {
        final total = value.duration.inMilliseconds;
        return bar(total == 0 ? 0 : value.position.inMilliseconds / total);
      },
    );
  }
}

/// Who watched my story.
class _ViewersSheet extends StatelessWidget {
  const _ViewersSheet({required this.load, required this.onOpen});

  final Future<List<StoryViewer>> Function() load;

  /// Tapped someone: their profile.
  final ValueChanged<StoryViewer> onOpen;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: FutureBuilder<List<StoryViewer>>(
          future: load(),
          builder: (context, snapshot) {
            final viewers = snapshot.data;
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text("Viewers couldn't load. Please try again."),
              );
            }
            if (viewers == null) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6),
              child: ListView(shrinkWrap: true, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Seen by ${viewers.length}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                if (viewers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text('No one yet. Check back later.',
                        style: TextStyle(color: HuntrColors.muted)),
                  ),
                for (final viewer in viewers)
                  ListTile(
                    key: Key('storyViewer-${viewer.userId}'),
                    onTap: () => onOpen(viewer),
                    leading: CircleAvatar(
                      backgroundColor: HuntrColors.surfaceHigh,
                      child: viewer.photoUrl == null
                          ? const Icon(Icons.person_outline)
                          : ClipOval(
                              child: Image.network(viewer.photoUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  webHtmlElementStrategy:
                                      WebHtmlElementStrategy.fallback)),
                    ),
                    title: Text(viewer.name.isEmpty ? 'Someone' : viewer.name),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (viewer.reaction case final reaction?) ...[
                        Text(reaction,
                            key: Key('viewerReaction-${viewer.userId}'),
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                      ],
                      Text(_ago(viewer.viewedAt),
                          style: const TextStyle(color: HuntrColors.muted)),
                    ]),
                  ),
              ]),
            );
          },
        ),
      );
}
