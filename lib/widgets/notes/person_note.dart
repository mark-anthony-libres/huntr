import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../profile/profile_section.dart';

/// The longest note (as on the backend).
const noteMaxLength = 500;

/// Whether [p] can have a note: a real person (not anonymous, not me).
bool canHaveNote(Profile p) => p.backendId != null && !p.isAnonymous;

/// Loads my note about them once (kept in [AppState]); quietly does nothing
/// without the backend or when it fails.
Future<void> loadNote(BuildContext context, int userId) async {
  final app = AppScope.read(context);
  final profiles = ServicesScope.profilesOf(context);
  final token = app.sessionToken;
  if (app.noteKnown(userId) || profiles == null || token == null) return;
  try {
    app.setNote(userId, await profiles.fetchNote(token, userId));
  } catch (error) {
    debugPrint('Note about $userId not loaded: $error');
  }
}

/// My private note about [p]: a sheet to write, change or delete it. Only I
/// ever see it.
Future<void> showPersonNote(BuildContext context, Profile p) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteSheet(profile: p),
    );

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.profile});

  final Profile profile;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _text = TextEditingController(
      text: AppScope.read(context).noteAbout(widget.profile.backendId!) ?? '');
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // not loaded yet (opened before the chat loaded it): now
    final userId = widget.profile.backendId!;
    if (!AppScope.read(context).noteKnown(userId)) {
      loadNote(context, userId).then((_) {
        if (mounted && _text.text.isEmpty) {
          _text.text = AppScope.read(context).noteAbout(userId) ?? '';
        }
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(String body) async {
    final app = AppScope.read(context);
    final profiles = ServicesScope.profilesOf(context);
    final token = app.sessionToken;
    final userId = widget.profile.backendId!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (profiles == null || token == null) {
      app.setNote(userId, body.trim());
      navigator.pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final kept = await profiles.saveNote(token, userId, body.trim());
      app.setNote(userId, kept);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            key: const Key('noteSaved'),
            content: Text(kept == null ? 'Note deleted' : 'Note saved')));
    } on SessionRejectedException {
      navigator.pop();
      app.endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Your note could not be saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final had =
        AppScope.of(context).noteAbout(widget.profile.backendId!) != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              'Note about ${widget.profile.name.isEmpty ? 'them' : widget.profile.name}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Only you can see this.',
              style: TextStyle(color: HuntrColors.muted)),
          const SizedBox(height: 14),
          TextField(
            key: const Key('noteField'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: noteMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                hintText: 'Where you met, what you talked about...'),
            onChanged: (_) => setState(() {}),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error,
                  key: const Key('noteError'),
                  style: const TextStyle(color: Color(0xFFFF9B8A))),
            ),
          Row(children: [
            if (had)
              TextButton(
                key: const Key('noteDelete'),
                style: TextButton.styleFrom(foregroundColor: HuntrColors.coral),
                onPressed: _saving ? null : () => _save(''),
                child: const Text('Delete'),
              ),
            const Spacer(),
            FilledButton(
              key: const Key('noteSave'),
              onPressed: _saving || (_text.text.trim().isEmpty && !had)
                  ? null
                  : () => _save(_text.text),
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// In a chat's header: a small note icon when I have a note about them
/// (tap: the note). Loads it the first time.
class NoteIcon extends StatefulWidget {
  const NoteIcon({super.key, required this.profile});

  final Profile profile;

  @override
  State<NoteIcon> createState() => _NoteIconState();
}

class _NoteIconState extends State<NoteIcon> {
  @override
  void initState() {
    super.initState();
    loadNote(context, widget.profile.backendId!);
  }

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).noteAbout(widget.profile.backendId!) == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        key: const Key('chatNoteIcon'),
        customBorder: const CircleBorder(),
        onTap: () => showPersonNote(context, widget.profile),
        child: Tooltip(
          message: 'Your note',
          child: Icon(Icons.sticky_note_2_outlined,
              size: 17, color: HuntrColors.orange),
        ),
      ),
    );
  }
}

/// On someone's profile: "Your note" (only I see it), or a button to add
/// one. Loads it the first time.
class PersonNoteSection extends StatefulWidget {
  const PersonNoteSection({super.key, required this.profile});

  final Profile profile;

  @override
  State<PersonNoteSection> createState() => _PersonNoteSectionState();
}

class _PersonNoteSectionState extends State<PersonNoteSection> {
  @override
  void initState() {
    super.initState();
    loadNote(context, widget.profile.backendId!);
  }

  @override
  Widget build(BuildContext context) {
    final note = AppScope.of(context).noteAbout(widget.profile.backendId!);
    if (note == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('profileAddNote'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => showPersonNote(context, widget.profile),
            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
            label: const Text('Add a private note'),
          ),
        ),
      );
    }
    return ProfileSection(
      title: 'Your note',
      child: InkWell(
        key: const Key('profileNote'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => showPersonNote(context, widget.profile),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HuntrColors.border),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note, style: const TextStyle(fontSize: 15.5, height: 1.45)),
            const SizedBox(height: 8),
            const Text('Only you can see this. Tap to edit.',
                style: TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}
