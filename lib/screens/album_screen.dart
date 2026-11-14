import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/nsfw_warning.dart';
import '../widgets/photo.dart';
import '../widgets/album/photo_viewer.dart';

/// A shared album: a grid, and a full-screen swipeable viewer on tap. With
/// Don't show NSFW content on Yes, a sensitive-content warning first (the
/// grid is built only after View album).
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.title, required this.photos});

  final String title;
  final List<AlbumPhoto> photos;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late bool _revealed = !(AppScope.maybeRead(context)?.hideNsfw ?? false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _revealed
          ? AlbumGrid(title: widget.title, photos: widget.photos)
          : SensitiveContentCover.album(
              onView: () => setState(() => _revealed = true),
              onCancel: () => Navigator.of(context).pop()),
    );
  }
}

/// An album as the people it's sent to see it: a grid, read-only; tap one to
/// open it full screen. Also my albums' "user view".
class AlbumGrid extends StatelessWidget {
  const AlbumGrid(
      {super.key, required this.title, required this.photos, this.header});

  final String title;
  final List<AlbumPhoto> photos;

  /// Shown above the grid (e.g. what this view is).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Column(children: [
        if (header != null) header!,
        const Expanded(child: Center(child: Text('No photos in this album'))),
      ]);
    }
    return CustomScrollView(slivers: [
      if (header != null) SliverToBoxAdapter(child: header),
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: photos.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PhotoViewer(photos: photos, initial: i, title: title),
            )),
            child: Hero(
                tag: 'photo-${photos[i].id}',
                child: PhotoArt(photo: photos[i], showLabel: true)),
          ),
        ),
      ),
    ]);
  }
}
