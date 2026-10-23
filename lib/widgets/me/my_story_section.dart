import 'package:flutter/material.dart';

import '../../screens/story_compose_screen.dart';
import '../../screens/my_stories_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../services/story_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../stories/story_ring.dart';

/// "Your story" on Me: add a story, or watch mine (with who saw it).
class MyStorySection extends StatefulWidget {
  const MyStorySection({super.key});

  @override
  State<MyStorySection> createState() => _MyStorySectionState();
}

class _MyStorySectionState extends State<MyStorySection> {
  List<Story>? _mine;

  StoryService? get _service => ServicesScope.storiesOf(context);

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

  Future<void> _add() async {
    final service = _service;
    if (service == null) return;
    if (await addToStory(context, service)) await _load();
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
    final mine = _mine ?? const <Story>[];
    final views = mine.fold<int>(0, (sum, s) => sum + (s.viewCount ?? 0));
    final has = mine.isNotEmpty;
    return Material(
      color: HuntrColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: HuntrColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('myStory'),
        onTap: has ? _watch : _add,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(
              width: 56,
              height: 56,
              child: has
                  ? StoryRing(
                      seen: false,
                      circle: true,
                      child: ClipOval(
                        child: Image.network(mine.last.thumbnailUrl,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                                color: HuntrColors.surfaceHigh)),
                      ),
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: HuntrColors.accentGradient,
                          shape: BoxShape.circle),
                      child: Icon(Icons.add_rounded,
                          color: Colors.black, size: 30),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your story',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      has
                          ? '${mine.length} ${mine.length == 1 ? 'story' : 'stories'} · Seen by $views'
                          : 'Share a ${StoryService.maxLength.inSeconds}-second video. Gone after 24 hours.',
                      style: const TextStyle(color: HuntrColors.muted),
                    ),
                  ]),
            ),
            if (has)
              IconButton.filledTonal(
                key: const Key('addStory'),
                tooltip: 'Add to your story',
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
              ),
          ]),
        ),
      ),
    );
  }
}
