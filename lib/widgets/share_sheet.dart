import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'share/album_option.dart';
import 'share/none_option.dart';

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
                  child: AlbumOption(
                    key: Key('pick-${a.id}'),
                    album: a,
                    selected: _albumId == a.id,
                    onTap: () => setState(() => _albumId = a.id),
                  ),
                ),
              if (albums.isNotEmpty)
                NoneOption(
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
