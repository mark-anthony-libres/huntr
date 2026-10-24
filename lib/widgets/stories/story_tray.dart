import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../screens/story_compose_screen.dart';
import '../../screens/story_viewer_screen.dart';
import '../../services/explore_service.dart';
import '../../services/huntr_backend.dart';
import '../../services/story_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../avatar.dart';
import '../load_more_row.dart';
import 'story_ring.dart';

/// The stories row at the top of Explore: Add Story, Your Story, then the
/// people nearby with a story (new ones first, then nearest), loaded a page
/// at a time as it's scrolled. Tapping someone plays their stories, then the
/// next person's.
class StoryTray extends StatefulWidget {
  const StoryTray({super.key, required this.service, required this.explore});

  final StoryService service;
  final ExploreService explore;

  @override
  State<StoryTray> createState() => _StoryTrayState();
}

class _StoryTrayState extends State<StoryTray> {
  List<Story>? _mine;

  /// The people with a story loaded so far, and where the next page starts
  /// (null: that's all of them).
  List<Profile> _people = const [];
  int? _next = 0;
  bool _loadingPeople = false;

  @override
  void initState() {
    super.initState();
    _loadMine();
    _loadPeople();
  }

  /// The first page again, or ([more]) the next one.
  Future<void> _loadPeople({bool more = false}) async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final offset = more ? _next : 0;
    if (token == null || offset == null || _loadingPeople) return;
    _loadingPeople = true;
    try {
      final page = await widget.explore.fetchStoryPeople(token, offset: offset);
      if (!mounted) return;
      setState(() {
        final known = {
          if (more)
            for (final p in _people) p.id
        };
        _people = [
          if (more) ..._people,
          for (final p in page.people)
            if (!known.contains(p.id)) p,
        ];
        _next = page.nextOffset;
      });
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('Stories tray not loaded: $error');
    } finally {
      _loadingPeople = false;
    }
  }

  Future<void> _loadMine() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null) return;
    try {
      final mine = await widget.service.mine(token);
      if (mounted) setState(() => _mine = mine);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('My stories not loaded: $error');
    }
  }

  Future<void> _add() async {
    if (await addToStory(context, widget.service)) await _loadMine();
  }

  /// The tray in order (mine first, when I have some), from [index]: ‹ and ›
  /// move along it, and each story that ends plays the next.
  Future<void> _watch(List<Profile> withStories, int index) async {
    final withMine = _mine?.isNotEmpty ?? false;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
            service: widget.service,
            me: withMine ? AppScope.read(context).myPublicProfile : null,
            people: withStories,
            start: index)));
    // watched ones move back (and grey), new ones show up
    await _loadPeople();
    if (withMine) await _loadMine();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // in the server's order: new stories first, then nearest
    final withStories = _people;
    final mine = _mine ?? const <Story>[];
    return SizedBox(
      height: 104,
      child: ListView(
        key: const Key('storyTray'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _TrayItem(
            key: const Key('trayAddStory'),
            label: 'Add Story',
            onTap: _add,
            // a dashed ring in the accent, a + inside: none yet, add one
            avatar: CustomPaint(
              painter: _DashedRing(color: HuntrColors.orange),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: HuntrColors.surface),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
          if (mine.isNotEmpty)
            _TrayItem(
              key: const Key('trayYourStory'),
              label: 'Your Story',
              onTap: () => _watch(withStories, 0),
              avatar: StoryRing(
                seen: false,
                circle: true,
                width: 3,
                child: ClipOval(
                    child:
                        ProfileArt(profile: app.myPublicProfile, fontSize: 20)),
              ),
            ),
          for (final (i, person) in withStories.indexed)
            _TrayItem(
              key: Key('trayStory-${person.id}'),
              label: person.shortName,
              faded: person.storySeen,
              onTap: () => _watch(withStories, mine.isEmpty ? i : i + 1),
              avatar: StoryRing(
                seen: person.storySeen,
                circle: true,
                width: 3,
                animate: true,
                child:
                    ClipOval(child: ProfileArt(profile: person, fontSize: 20)),
              ),
            ),
          // the next page, once the end of the row is reached
          if (_next != null && _people.isNotEmpty)
            LoadMoreRow(
              key: ValueKey('tray-more-${_people.length}'),
              onVisible: () => _loadPeople(more: true),
            ),
        ],
      ),
    );
  }
}

class _TrayItem extends StatelessWidget {
  const _TrayItem({
    super.key,
    required this.label,
    required this.avatar,
    required this.onTap,
    this.faded = false,
  });

  final String label;
  final Widget avatar;
  final VoidCallback onTap;
  final bool faded;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 78,
            child: Column(children: [
              const SizedBox(height: 6),
              SizedBox(width: 66, height: 66, child: avatar),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: faded ? HuntrColors.muted : Colors.white)),
            ]),
          ),
        ),
      );
}

/// A ring of short dashes round a circle (Add Story).
class _DashedRing extends CustomPainter {
  const _DashedRing({required this.color});

  final Color color;

  static const _dashes = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = (Offset.zero & size).deflate(1.5);
    const sweep = 2 * math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing oldDelegate) => oldDelegate.color != color;
}
