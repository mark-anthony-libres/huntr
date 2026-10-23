import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../album/add_photo_tile.dart';
import '../photo.dart';
import '../photos/cached_photo_image.dart';
import '../reorderable_tile.dart';

/// Dots showing how many of the allowed profile photos are used.
class PhotoCountDots extends StatelessWidget {
  const PhotoCountDots({super.key, required this.used, required this.max});

  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < used ? HuntrColors.orange : HuntrColors.surfaceHigh,
            ),
          ),
        const SizedBox(width: 6),
        Text('$used/$max', style: const TextStyle(color: HuntrColors.muted)),
      ],
    );
  }
}

/// My saved profile photos (default first, marked "Main"), each with a quick
/// remove button, plus a dashed "Add photo" tile while there's room. Hold a
/// photo and drag it to rearrange them (the first is Main).
class ProfilePhotoGrid extends StatelessWidget {
  const ProfilePhotoGrid({
    super.key,
    required this.photos,
    required this.canAdd,
    required this.uploading,
    required this.onOpen,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
    this.removing = const {},
  });

  /// Moves the photo at `from` to `to`.
  final void Function(int from, int to) onMove;

  final List<ProfilePhoto> photos;
  final bool canAdd;

  /// An upload is in progress: the add tile shows a spinner.
  final bool uploading;
  final ValueChanged<ProfilePhoto> onOpen;
  final VoidCallback onAdd;

  /// Removes the photo right away (no confirmation).
  final ValueChanged<ProfilePhoto> onRemove;

  /// Photos being removed: their remove button shows a spinner.
  final Set<int> removing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        // at least 3 columns; more on wide screens, so tiles stay a sensible size
        crossAxisCount: (constraints.maxWidth / 180).floor().clamp(3, 6),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
        children: [
          for (final (index, photo) in photos.indexed)
            ReorderableTile(
              key: Key('reorderProfilePhoto-${photo.id}'),
              index: index,
              onMove: onMove,
              enabled: !removing.contains(photo.id),
              child: _PhotoTile(
                photo: photo,
                onTap: () => onOpen(photo),
                onRemove: () => onRemove(photo),
                removing: removing.contains(photo.id),
              ),
            ),
          if (uploading)
            const _UploadingTile()
          else if (canAdd)
            AddPhotoTile(
                key: const Key('addProfilePhoto'),
                label: 'Add photo',
                onTap: onAdd),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.onTap,
    required this.onRemove,
    required this.removing,
  });

  final ProfilePhoto photo;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HuntrColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HuntrColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('profilePhoto-${photo.id}'),
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          CachedPhotoImage(photo),
          Positioned(
            top: 6,
            right: 6,
            child: _RemoveButton(
                key: Key('removeProfilePhoto-${photo.id}'),
                removing: removing,
                onPressed: removing ? null : onRemove),
          ),
          if (photo.isDefault)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: HuntrColors.accentGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Main',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton(
      {super.key, required this.removing, required this.onPressed});

  final bool removing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 32,
        height: 32,
        child: removing
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : IconButton(
                tooltip: 'Remove photo',
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onPressed,
              ),
      ),
    );
  }
}

class _UploadingTile extends StatelessWidget {
  const _UploadingTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profilePhotoUploading'),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.6)),
      ),
      child:
          const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(height: 10),
        Text('Uploading...', style: TextStyle(color: HuntrColors.muted)),
      ]),
    );
  }
}

/// A private album in the list: cover, name, count, chevron.
class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              SizedBox(
                width: 60,
                height: 60,
                child: album.photos.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: HuntrColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.photo_library_outlined,
                            color: HuntrColors.muted),
                      )
                    : PhotoArt(
                        photo: album.photos.first, radius: 10, iconSize: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${album.contentsLabel} · Private',
                        style: const TextStyle(color: HuntrColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: HuntrColors.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
