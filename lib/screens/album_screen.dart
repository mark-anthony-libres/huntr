import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/photo.dart';

/// A shared album: a grid, and a full-screen swipeable viewer on tap.
class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.title, required this.photos});

  final String title;
  final List<AlbumPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: photos.isEmpty
          ? const Center(child: Text('No photos in this album'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      _PhotoViewer(photos: photos, initial: i, title: title),
                )),
                child: Hero(
                    tag: 'photo-${photos[i].id}',
                    child: PhotoArt(photo: photos[i], showLabel: true)),
              ),
            ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer(
      {required this.photos, required this.initial, required this.title});
  final List<AlbumPhoto> photos;
  final int initial;
  final String title;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_index + 1} of ${widget.photos.length}'),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Hero(
                tag: 'photo-${widget.photos[i].id}',
                child: PhotoArt(
                    photo: widget.photos[i],
                    radius: 20,
                    iconSize: 72,
                    showLabel: true),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
