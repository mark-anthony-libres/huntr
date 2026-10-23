import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/photo.dart';
import '../flows/my_albums.dart';
import '../services/services_scope.dart';
import '../widgets/album/photo_viewer.dart';
import 'album_screen.dart';
import '../widgets/album/remove_dot.dart';
import '../widgets/album/add_photo_tile.dart';
import '../widgets/reorderable_tile.dart';

/// Edit one of my private albums: rename, add, rearrange (hold and drag) and
/// remove photos (and, on the backend, videos and cropping), delete. Without a backend the album is
/// kept on this device with sample photos.
class MyAlbumScreen extends StatefulWidget {
  const MyAlbumScreen({super.key, required this.albumId});
  final String albumId;

  @override
  State<MyAlbumScreen> createState() => _MyAlbumScreenState();
}

class _MyAlbumScreenState extends State<MyAlbumScreen> {
  bool _adding = false;

  /// Showing the album as the people it's sent to see it (read-only).
  bool _userView = false;

  /// Items being changed (removed or cropped): their buttons are locked.
  final Set<String> _busy = {};

  bool get _onBackend => ServicesScope.albumsOf(context) != null;

  Future<void> _add(AppState app, Album album) async {
    if (!_onBackend) {
      final s = await pickSamplePhoto(context);
      if (s != null) app.addPhotoToAlbum(album.id, s);
      return;
    }
    final albums = MyAlbums.of(context);
    setState(() => _adding = true);
    await albums.add(album);
    if (mounted) setState(() => _adding = false);
  }

  Future<void> _change(AlbumPhoto photo, Future<bool> Function() change) async {
    if (_busy.contains(photo.id)) return;
    setState(() => _busy.add(photo.id));
    await change();
    if (mounted) setState(() => _busy.remove(photo.id));
  }

  void _remove(AppState app, Album album, AlbumPhoto photo) {
    final stored = photo.stored;
    if (stored == null) return app.removePhotoFromAlbum(album.id, photo.id);
    final albums = MyAlbums.of(context);
    _change(photo, () => albums.remove(album, stored));
  }

  void _move(AppState app, Album album, int from, int to) {
    if (_busy.isNotEmpty) return; // not while one is changing
    if (!_onBackend) return app.movePhotoInAlbum(album.id, from, to);
    MyAlbums.of(context).move(album, from, to);
  }

  void _crop(Album album, AlbumPhoto photo) {
    final albums = MyAlbums.of(context);
    _change(photo, () => albums.recrop(album, photo.stored!));
  }

  Future<void> _rename(AppState app, Album album) async {
    final name = await promptAlbumName(context,
        initial: album.name, title: 'Rename album');
    if (name == null || !mounted) return;
    if (_onBackend) {
      await MyAlbums.of(context).rename(album, name.trim());
    } else {
      app.renameAlbum(album.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final album = app.myAlbumById(widget.albumId);
    if (album == null) {
      return const Scaffold(
          body: Center(child: Text('This album was deleted.')));
    }
    final limits = app.albumLimits;
    final full = limits != null && album.photos.length >= limits.maxItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(album.name),
        actions: [
          if (!_userView) ...[
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: () => _rename(app, album),
            ),
            IconButton(
              tooltip: 'Delete album',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, app, album),
            ),
          ],
          // switch between editing and how the people it's sent to see it
          IconButton(
            key: const Key('albumUserView'),
            tooltip: _userView ? 'Back to editing' : 'User view',
            isSelected: _userView,
            icon: const Icon(Icons.visibility_outlined),
            selectedIcon: const Icon(Icons.edit_outlined),
            onPressed: () => setState(() => _userView = !_userView),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _userView
          ? AlbumGrid(
              title: album.name,
              photos: album.photos,
              header: const _UserViewNote(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  limits == null
                      ? 'Private. Only sent when you pick this album while sending or accepting a chat request. '
                          'Hold and drag to rearrange.'
                      : 'Private. Only sent when you pick this album while sending or accepting a chat request. '
                          'Up to ${limits.maxItems} photos and videos (videos up to ${limits.maxVideoSeconds} seconds). '
                          'Hold and drag to rearrange.',
                  style: const TextStyle(color: HuntrColors.muted),
                ),
                const SizedBox(height: 14),
                if (album.photos.isEmpty && !_adding)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('No photos or videos yet.'),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) => GridView.count(
                    // at least 3 columns; more on wide screens
                    crossAxisCount:
                        (constraints.maxWidth / 200).floor().clamp(3, 6),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final (index, ph) in album.photos.indexed)
                        ReorderableTile(
                          key: Key('reorderAlbumItem-${ph.id}'),
                          index: index,
                          radius: 12, // PhotoArt's corners
                          enabled: _busy.isEmpty,
                          onMove: (from, to) => _move(app, album, from, to),
                          child: Stack(fit: StackFit.expand, children: [
                            GestureDetector(
                              key: Key('albumItem-${ph.id}'),
                              // the photo or video itself, full screen
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => PhotoViewer(
                                          photos: album.photos,
                                          initial: index,
                                          title: album.name))),
                              child: PhotoArt(
                                  photo: ph, showLabel: ph.stored == null),
                            ),
                            if (_busy.contains(ph.id))
                              const ColoredBox(
                                color: Colors.black45,
                                child:
                                    Center(child: CircularProgressIndicator()),
                              )
                            else ...[
                              if (ph.stored != null && !ph.stored!.isVideo)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: _TileButton(
                                    key: Key('cropAlbumItem-${ph.id}'),
                                    icon: Icons.crop,
                                    label: 'Crop photo',
                                    onTap: () => _crop(album, ph),
                                  ),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: RemoveDot(
                                    key: Key('removeAlbumItem-${ph.id}'),
                                    onTap: () => _remove(app, album, ph)),
                              ),
                            ],
                          ]),
                        ),
                      if (_adding)
                        const DecoratedBox(
                          decoration:
                              BoxDecoration(color: HuntrColors.surfaceHigh),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (!full)
                        AddPhotoTile(
                          key: const Key('addAlbumPhoto'),
                          label:
                              _onBackend ? 'Add photo or video' : 'Add photo',
                          onTap: () => _add(app, album),
                        ),
                    ],
                  ),
                ),
                if (full) ...[
                  const SizedBox(height: 10),
                  Text(
                      'This album is full. It can hold up to ${limits.maxItems} photos and videos.',
                      key: const Key('albumFull'),
                      style: const TextStyle(color: HuntrColors.muted)),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState app, Album album) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${album.name}"?'),
        content: Text(_onBackend
            ? 'Its photos and videos are deleted too. Albums you already sent in chats stay there.'
            : 'Albums you already sent in chats stay there.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('confirmDeleteAlbum'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (_onBackend) {
      final albums = MyAlbums.of(context);
      final navigator = Navigator.of(context);
      if (await albums.delete(album)) navigator.pop();
      return;
    }
    app.deleteAlbum(album.id);
    Navigator.pop(context);
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration:
            const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Icon(icon, size: 15, semanticLabel: label),
      ),
    );
  }
}

/// Until camera and gallery upload exist, adding a photo picks a sample subject.
Future<PhotoSubject?> pickSamplePhoto(BuildContext context) {
  return showModalBottomSheet<PhotoSubject>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a photo', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                  'Sample photos for now. Camera and gallery upload come with the backend.',
                  style: TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in PhotoSubject.values)
                  ActionChip(
                    avatar: Icon(s.icon, size: 18),
                    label: Text(s.label),
                    onPressed: () => Navigator.pop(ctx, s),
                  ),
              ]),
            ]),
      ),
    ),
  );
}

Future<String?> promptAlbumName(BuildContext context,
    {String initial = '', String title = 'New album'}) {
  final c = TextEditingController(text: initial);
  // as long as the backend allows (it checks too)
  final maxLength = AppScope.read(context).albumLimits?.maxNameLength;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('albumName'),
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLength: maxLength,
        decoration:
            const InputDecoration(hintText: 'e.g. Weekend, Gym, Private'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save')),
      ],
    ),
  );
}

/// Above the "user view": what it is.
class _UserViewNote extends StatelessWidget {
  const _UserViewNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HuntrColors.active.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuntrColors.active.withValues(alpha: 0.4)),
      ),
      child: const Row(children: [
        Icon(Icons.visibility_outlined, color: HuntrColors.active, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
              'User view: this is how people see this album when you send it.',
              style: TextStyle(color: HuntrColors.muted)),
        ),
      ]),
    );
  }
}
