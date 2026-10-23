import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../photo.dart';

class AlbumOption extends StatelessWidget {
  const AlbumOption(
      {super.key,
      required this.album,
      required this.selected,
      required this.onTap});
  final Album album;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? HuntrColors.orange.withValues(alpha: 0.12)
          : HuntrColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? HuntrColors.orange : Colors.transparent,
            width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            SizedBox(
              width: 56,
              height: 56,
              child: album.photos.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                          color: HuntrColors.surface,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.photo_library_outlined,
                          color: HuntrColors.muted),
                    )
                  : PhotoArt(photo: album.photos.first, iconSize: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(album.contentsLabel,
                        style: const TextStyle(color: HuntrColors.muted)),
                  ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? HuntrColors.orange : HuntrColors.muted),
          ]),
        ),
      ),
    );
  }
}
