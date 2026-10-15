import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/photo.dart';
import 'album_screen.dart';

/// Edit one of my private albums: rename, add and remove photos, delete.
class MyAlbumScreen extends StatelessWidget {
  const MyAlbumScreen({super.key, required this.albumId});
  final String albumId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final album = app.myAlbumById(albumId);
    if (album == null) {
      return const Scaffold(
          body: Center(child: Text('This album was deleted.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(album.name),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () async {
              final name = await promptAlbumName(context,
                  initial: album.name, title: 'Rename album');
              if (name != null) app.renameAlbum(album.id, name);
            },
          ),
          IconButton(
            tooltip: 'Delete album',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, app, album),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Private. Only sent when you pick this album while sending or accepting a chat request.',
            style: TextStyle(color: HuntrColors.muted),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final ph in album.photos)
                Stack(fit: StackFit.expand, children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AlbumScreen(
                            title: album.name, photos: album.photos))),
                    child: PhotoArt(photo: ph, showLabel: true),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _RemoveDot(
                        onTap: () => app.removePhotoFromAlbum(album.id, ph.id)),
                  ),
                ]),
              AddPhotoTile(
                key: const Key('addAlbumPhoto'),
                onTap: () async {
                  final s = await pickSamplePhoto(context);
                  if (s != null) app.addPhotoToAlbum(album.id, s);
                },
              ),
            ],
          ),
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
        content: const Text('Albums you already sent in chats stay there.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    app.deleteAlbum(album.id);
    Navigator.pop(context);
  }
}

class _RemoveDot extends StatelessWidget {
  const _RemoveDot({required this.onTap});
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
        child: const Icon(Icons.close, size: 15, semanticLabel: 'Remove photo'),
      ),
    );
  }
}

class AddPhotoTile extends StatelessWidget {
  const AddPhotoTile({super.key, required this.onTap, this.label = 'Add'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: HuntrColors.amber.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_photo_alternate_outlined,
              color: HuntrColors.amber),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 12, color: HuntrColors.amber)),
        ]),
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
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('albumName'),
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
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
