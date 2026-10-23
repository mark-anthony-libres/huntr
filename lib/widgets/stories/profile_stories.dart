import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../screens/story_viewer_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../network_photo.dart';

/// "Story" on a profile: a row of the person's story thumbnails (tap one to
/// watch from it) and "View all"; nothing when they have none. [mine]: my
/// own, in my profile preview, shown just as others see them (no Add Story,
/// no view counts: those are on Me and in my story's Seen by).
class ProfileStories extends StatefulWidget {
  const ProfileStories({super.key, required this.profile, this.mine = false});

  final Profile profile;
  final bool mine;

  @override
  State<ProfileStories> createState() => _ProfileStoriesState();
}

class _ProfileStoriesState extends State<ProfileStories> {
  List<Story>? _stories;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_asked) {
      _asked = true;
      _load();
    }
  }

  Future<void> _load() async {
    final service = ServicesScope.storiesOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final userId = widget.profile.backendId;
    if (service == null || token == null) return;
    // someone else's: only when they have any
    if (!widget.mine && (userId == null || !widget.profile.hasStory)) return;
    try {
      final stories = widget.mine
          ? await service.mine(token)
          : await service.of(token, userId!);
      if (mounted) setState(() => _stories = stories);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('Profile stories not loaded: $error');
    }
  }

  Future<void> _watch(Story? from) async {
    final service = ServicesScope.storiesOf(context);
    if (service == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => widget.mine
            ? StoryViewerScreen.mine(
                service: service,
                me: AppScope.read(context).myPublicProfile,
                startStoryId: from?.id)
            : StoryViewerScreen(
                service: service,
                people: [widget.profile],
                startStoryId: from?.id)));
    if (mounted) await _load(); // seen marks, deletions
  }

  @override
  Widget build(BuildContext context) {
    if (ServicesScope.storiesOf(context) == null) {
      return const SizedBox.shrink();
    }
    final stories = _stories ?? const <Story>[];
    if (stories.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('profileStories'),
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Story',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(
            key: const Key('storiesViewAll'),
            // from the first one I haven't watched
            onPressed: () => _watch(null),
            style: TextButton.styleFrom(
                foregroundColor: HuntrColors.muted,
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('View all (${stories.length})'),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 128,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final story in stories)
                _StoryTile(story: story, onTap: () => _watch(story)),
            ],
          ),
        ),
      ]),
    );
  }
}

const _tileWidth = 86.0;
final _tileShape = BorderRadius.circular(12);

/// A story's thumbnail.
class _StoryTile extends StatelessWidget {
  const _StoryTile({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: HuntrColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: _tileShape,
              side: const BorderSide(color: Colors.white24)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('profileStory-${story.id}'),
            onTap: onTap,
            child: SizedBox(
              width: _tileWidth,
              child: Stack(fit: StackFit.expand, children: [
                NetworkPhoto(story.thumbnailUrl),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.25, 0.7, 1],
                      colors: [
                        Color(0x66000000),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0x99000000),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
