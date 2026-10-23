import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/story_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'story_compose_screen.dart';
import 'story_viewer_screen.dart';

/// My stories as a grid, each with how many watched it; tapping one offers
/// View story and Delete (stories can't be saved or shared, for privacy).
class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({super.key, required this.service});

  final StoryService service;

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen> {
  List<Story>? _mine;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null) return;
    try {
      final mine = await widget.service.mine(token);
      if (mounted) {
        setState(() {
          _mine = mine;
          _error = null;
        });
      }
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = "Your stories couldn't load. Check your connection.");
      }
    }
  }

  Future<void> _view() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StoryViewerScreen.mine(
            service: widget.service,
            me: AppScope.read(context).myPublicProfile)));
    await _load();
  }

  Future<void> _add() async {
    if (await addToStory(context, widget.service)) await _load();
  }

  Future<void> _actions(Story story) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('myStory-view'),
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('View story'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.visibility_outlined,
                  size: 16, color: HuntrColors.muted),
              const SizedBox(width: 4),
              Text('${story.viewCount ?? 0}',
                  style: const TextStyle(color: HuntrColors.muted)),
            ]),
            onTap: () => Navigator.pop(context, 'view'),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            key: const Key('myStory-delete'),
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
      case 'view':
        await _view();
      case 'delete':
        await _delete(story);
    }
  }

  Future<void> _delete(Story story) async {
    final token = AppScope.read(context).sessionToken;
    final messenger = ScaffoldMessenger.of(context);
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
    if (!confirmed) return;
    try {
      await widget.service.delete(token, story.id);
      await _load();
    } catch (error) {
      messenger.showSnackBar(const SnackBar(
          content: Text("The story wasn't deleted. Please try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return Scaffold(
      appBar: AppBar(title: const Text('Your stories')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addStoryFromGrid'),
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add story'),
      ),
      body: mine == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!))
          : mine.isEmpty
              ? const Center(
                  child: Text('No stories right now. Add one!',
                      style: TextStyle(color: HuntrColors.muted)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      childAspectRatio: 9 / 16,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10),
                  itemCount: mine.length,
                  itemBuilder: (_, i) => _StoryTile(
                      story: mine[i], onTap: () => _actions(mine[i])),
                ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hours = DateTime.now().difference(story.postedAt).inHours;
    return Material(
      color: HuntrColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HuntrColors.border),
      ),
      child: InkWell(
        key: Key('myStoryTile-${story.id}'),
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          Image.network(story.thumbnailUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: HuntrColors.surfaceHigh)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.25, 0.7, 1],
                colors: [
                  Color(0x99000000),
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xB3000000)
                ],
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: Text(hours < 1 ? 'Just now' : '${hours}h ago',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Row(children: [
              const Icon(Icons.visibility_outlined,
                  size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text('${story.viewCount ?? 0}',
                  key: Key('myStoryViews-${story.id}'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ]),
          ),
        ]),
      ),
    );
  }
}
