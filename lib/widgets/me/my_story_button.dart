import 'package:flutter/material.dart';

import '../../screens/story_compose_screen.dart';
import '../../screens/my_stories_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../services/story_service.dart';
import '../../services/story_upload.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// My story, on my photo on Me: "Add story", or "Your story" to watch mine
/// (with who saw it) plus a + to add another. While one goes up it shows
/// how far it is.
class MyStoryButton extends StatefulWidget {
  const MyStoryButton({super.key});

  @override
  State<MyStoryButton> createState() => _MyStoryButtonState();
}

class _MyStoryButtonState extends State<MyStoryButton> {
  List<Story>? _mine;

  StoryService? get _service => ServicesScope.storiesOf(context);

  /// Stories posted in the background so far ([storyUpload]): one more,
  /// and mine load again.
  int _posted = storyUpload.posted;

  @override
  void initState() {
    super.initState();
    storyUpload.addListener(_uploadChanged);
  }

  @override
  void dispose() {
    storyUpload.removeListener(_uploadChanged);
    super.dispose();
  }

  void _uploadChanged() {
    if (!mounted) return;
    if (storyUpload.posted != _posted) {
      _posted = storyUpload.posted;
      _load();
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mine == null) _load();
  }

  Future<void> _load() async {
    final service = _service;
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (service == null || token == null) return;
    try {
      final mine = await service.mine(token);
      if (mounted) setState(() => _mine = mine);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('My stories not loaded: $error');
    }
  }

  /// It goes up in the background: this shows how far it is, and mine
  /// load again once it's up.
  Future<void> _add() async {
    final service = _service;
    if (service == null) return;
    await addToStory(context, service);
  }

  void _retry() {
    final messenger = ScaffoldMessenger.of(context);
    storyUpload
        .retry()
        .then((posted) => announceStoryUpload(messenger, posted));
  }

  /// My stories as a grid (views, share, save, delete).
  Future<void> _watch() async {
    final service = _service;
    if (service == null) return;
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MyStoriesScreen(service: service)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) return const SizedBox.shrink();
    final has = _mine?.isNotEmpty ?? false;
    final progress = storyUpload.progress;
    final failed = storyUpload.error;
    if (progress != null) {
      return _Pill(
        icon: const SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        label: progress < 1
            ? 'Posting ${(progress * 100).round()}%'
            : 'Getting it ready…',
      );
    }
    if (failed != null) {
      return Tooltip(
        message: failed,
        child: _Pill(
          key: const Key('myStory'),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: 'Try again',
          accent: HuntrColors.coral,
          onTap: _retry,
        ),
      );
    }
    if (!has) {
      return _Pill(
        key: const Key('myStory'),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: 'Add story',
        accent: HuntrColors.orange,
        onTap: _add,
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _Pill(
        key: const Key('myStory'),
        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
        label: 'Your story',
        accent: HuntrColors.orange,
        onTap: _watch,
      ),
      const SizedBox(width: 6),
      _Pill(
        key: const Key('addStory'),
        icon: const Icon(Icons.add_rounded, size: 18),
        tooltip: 'Add to your story',
        accent: HuntrColors.orange,
        onTap: _add,
      ),
    ]);
  }
}

/// A small dark pill on the photo; just the icon when there's no [label].
class _Pill extends StatelessWidget {
  const _Pill(
      {super.key,
      required this.icon,
      this.label,
      this.tooltip,
      this.accent,
      this.onTap});

  final Widget icon;
  final String? label;
  final String? tooltip;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.white;
    final pill = Material(
      color: HuntrColors.night.withValues(alpha: 0.72),
      shape: StadiumBorder(
          side: BorderSide(
              color: accent ?? Colors.white.withValues(alpha: 0.18))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconTheme(data: IconThemeData(color: color), child: icon),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label!,
                  style: TextStyle(
                      color: accent == null ? Colors.white : color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}
