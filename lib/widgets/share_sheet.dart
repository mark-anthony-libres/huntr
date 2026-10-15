import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'photo.dart';

/// What the user picked in [showShareSheet].
class ShareChoice {
  const ShareChoice({this.albumId, this.note = ''});

  /// The album to send, or null to share none.
  final String? albumId;
  final String note;
}

/// Bottom sheet for sending or accepting a chat request: pick which of my albums to share,
/// and optionally add a note. Returns null if dismissed.
Future<ShareChoice?> showShareSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String actionLabel,
  required IconData actionIcon,
  bool withNote = false,
}) {
  return showModalBottomSheet<ShareChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
      withNote: withNote,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.withNote,
  });
  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final bool withNote;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _note = TextEditingController();
  String? _albumId;
  bool _init = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = AppScope.of(context).myAlbums;
    if (!_init) {
      _albumId = albums.isEmpty ? null : albums.first.id;
      _init = true;
    }
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(widget.subtitle,
                  style: const TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 16),
              Text('ALBUM TO SHARE',
                  style: text.labelMedium
                      ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              if (albums.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                      'You have no albums yet. Create one under Me → Albums. You can still continue without one.'),
                ),
              for (final a in albums)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AlbumOption(
                    key: Key('pick-${a.id}'),
                    album: a,
                    selected: _albumId == a.id,
                    onTap: () => setState(() => _albumId = a.id),
                  ),
                ),
              if (albums.isNotEmpty)
                _NoneOption(
                    selected: _albumId == null,
                    onTap: () => setState(() => _albumId = null)),
              if (widget.withNote) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final n in requestNotes)
                    ActionChip(label: Text(n), onPressed: () => _note.text = n),
                ]),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('requestNote'),
                  controller: _note,
                  maxLength: 120,
                  decoration: const InputDecoration(
                      hintText: 'Add a short note (optional)'),
                ),
              ],
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: const BoxDecoration(
                    gradient: HuntrColors.accentGradient,
                    borderRadius: BorderRadius.all(Radius.circular(30))),
                child: FilledButton.icon(
                  key: const Key('confirmShare'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: Icon(widget.actionIcon),
                  label: Text(widget.actionLabel),
                  onPressed: () => Navigator.pop(context,
                      ShareChoice(albumId: _albumId, note: _note.text)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumOption extends StatelessWidget {
  const _AlbumOption(
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
          ? HuntrColors.amber.withValues(alpha: 0.12)
          : HuntrColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? HuntrColors.amber : Colors.transparent,
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
                    Text('${album.photos.length} photos',
                        style: const TextStyle(color: HuntrColors.muted)),
                  ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? HuntrColors.amber : HuntrColors.muted),
          ]),
        ),
      ),
    );
  }
}

class _NoneOption extends StatelessWidget {
  const _NoneOption({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: const Icon(Icons.block, color: HuntrColors.muted),
      title: const Text('Don\'t share an album'),
      trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? HuntrColors.amber : HuntrColors.muted),
      onTap: onTap,
    );
  }
}
