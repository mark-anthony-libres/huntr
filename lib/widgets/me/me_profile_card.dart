import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../photos/cached_photo_image.dart';

/// The top of Me: my photos big (swipe through them), my story on top, my
/// name and bio over the bottom with Edit profile and Preview, and a row of
/// my photos under it.
class MeProfileCard extends StatefulWidget {
  const MeProfileCard({
    super.key,
    required this.name,
    required this.age,
    required this.bio,
    required this.photos,
    required this.maxPhotos,
    required this.placeholder,
    required this.story,
    required this.onEdit,
    required this.onPreview,
  });

  final String name;
  final int age;
  final String bio;

  /// My profile photos, the main one first.
  final List<ProfilePhoto> photos;

  /// The most I can have (null until known: the row offers to add one).
  final int? maxPhotos;

  /// Shown until I have a photo (my character avatar).
  final Widget placeholder;

  /// At the top right of the photo.
  final Widget story;
  final VoidCallback onEdit;
  final VoidCallback onPreview;

  @override
  State<MeProfileCard> createState() => _MeProfileCardState();
}

class _MeProfileCardState extends State<MeProfileCard> {
  final _pages = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(MeProfileCard old) {
    super.didUpdateWidget(old);
    // a photo was removed or reordered: back to the main one
    if (_page >= widget.photos.length ||
        old.photos.firstOrNull?.id != widget.photos.firstOrNull?.id) {
      _page = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int index) => _pages.animateToPage(index,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return LayoutBuilder(builder: (context, box) {
      final height = (box.maxWidth * 0.95).clamp(300.0, 460.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(26),
            border:
                Border.all(color: HuntrColors.orange.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (photos.isEmpty)
              widget.placeholder
            else
              PageView.builder(
                key: const Key('mePhotos'),
                controller: _pages,
                itemCount: photos.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (_, i) => CachedPhotoImage(photos[i]),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _NameAndActions(
                name: widget.name,
                age: widget.age,
                bio: widget.bio,
                onEdit: widget.onEdit,
                onPreview: widget.onPreview,
              ),
            ),
            if (photos.length > 1)
              Positioned(
                top: 12,
                left: 12,
                child: _Count(
                    key: const Key('mePhotoCount'),
                    text: '${_page + 1} of ${photos.length}'),
              ),
            Positioned(top: 12, right: 12, child: widget.story),
          ]),
        ),
        const SizedBox(height: 12),
        _PhotoRow(
          photos: photos,
          canAdd: widget.maxPhotos == null || photos.length < widget.maxPhotos!,
          selected: _page,
          onOpen: _show,
          onAdd: widget.onEdit,
        ),
      ]);
    });
  }
}

class _NameAndActions extends StatelessWidget {
  const _NameAndActions({
    required this.name,
    required this.age,
    required this.bio,
    required this.onEdit,
    required this.onPreview,
  });

  final String name;
  final int age;
  final String bio;
  final VoidCallback onEdit;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HuntrColors.night.withValues(alpha: 0),
            HuntrColors.night.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name, $age',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 6),
            if (bio.isEmpty)
              OutlinedButton.icon(
                key: const Key('addBio'),
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                  textStyle: const TextStyle(
                      fontFamily: huntrFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add a bio'),
              )
            else
              Text(bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 14.5,
                      height: 1.4)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: HuntrColors.accentGradient,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: FilledButton.icon(
                    key: const Key('editProfile'),
                    onPressed: onEdit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
                      textStyle: const TextStyle(
                          fontFamily: huntrFontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit profile',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('viewMyProfile'),
                  onPressed: onPreview,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: HuntrColors.night.withValues(alpha: 0.7),
                    minimumSize: const Size.fromHeight(48),
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                    textStyle: const TextStyle(
                        fontFamily: huntrFontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Preview',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// "2 of 4": which photo is showing.
class _Count extends StatelessWidget {
  const _Count({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: ShapeDecoration(
        color: HuntrColors.night.withValues(alpha: 0.6),
        shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.photo_library_outlined, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// My photos small, under the big one: tap one to show it, + to add one.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photos,
    required this.canAdd,
    required this.selected,
    required this.onOpen,
    required this.onAdd,
  });

  final List<ProfilePhoto> photos;
  final bool canAdd;
  final int selected;
  final ValueChanged<int> onOpen;
  final VoidCallback onAdd;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final count = photos.length + (canAdd ? 1 : 0);
    return LayoutBuilder(builder: (context, box) {
      final columns = count > 5 ? count : 5;
      final width = (box.maxWidth - _gap * (columns - 1)) / columns;
      final size = Size(width, width / 0.85);
      return Row(children: [
        for (final (i, photo) in photos.indexed) ...[
          if (i > 0) const SizedBox(width: _gap),
          SizedBox.fromSize(
            size: size,
            child: Material(
              color: HuntrColors.surfaceHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: i == selected
                    ? BorderSide(color: HuntrColors.orange, width: 2)
                    : const BorderSide(color: HuntrColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('mePhoto-${photo.id}'),
                onTap: () => onOpen(i),
                child: CachedPhotoImage(photo),
              ),
            ),
          ),
        ],
        if (canAdd) ...[
          if (photos.isNotEmpty) const SizedBox(width: _gap),
          SizedBox.fromSize(
            size: size,
            child: Tooltip(
              message: 'Add a photo',
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF4A4B55), width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('meAddPhoto'),
                  onTap: onAdd,
                  child: Icon(Icons.add_rounded, color: HuntrColors.orange),
                ),
              ),
            ),
          ),
        ],
      ]);
    });
  }
}
