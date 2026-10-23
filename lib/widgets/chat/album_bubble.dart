import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../screens/album_screen.dart';
import '../../theme.dart';
import '../photo.dart';

/// A shared album, shown as a card with a preview grid. Tap to open the full album.
class AlbumBubble extends StatelessWidget {
  const AlbumBubble(
      {super.key, required this.message, required this.ownerName});
  final Message message;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    final width = MediaQuery.sizeOf(context).width * 0.72;
    void open() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AlbumScreen(
              title: '$ownerName "${message.albumName ?? 'album'}"',
              photos: message.album),
        ));
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: width.clamp(220, 340),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.photo_library_rounded,
                size: 18, color: HuntrColors.orange),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message.text,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),
          AlbumPreview(photos: message.album, maxTiles: 3, onTap: open),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: open,
                child: Text('View ${message.album.length} photos')),
          ),
        ]),
      ),
    );
  }
}
