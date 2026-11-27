import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/huntr_backend.dart' show BackendException;
import '../../state/messaging_state.dart';
import '../../theme.dart';
import '../chat/reactions.dart' show firstReactionOf, quickReactionsOf;

/// Someone's bio, and under it: react with one of my quick reactions (a
/// double tap on the bio gives the first, as on a message), or reply. Each
/// goes to our direct chat, with their bio quoted over it.
class BioReplyRow extends StatefulWidget {
  const BioReplyRow({super.key, required this.profile, required this.bio});

  final Profile profile;

  /// The bio itself.
  final Widget bio;

  @override
  State<BioReplyRow> createState() => _BioReplyRowState();
}

class _BioReplyRowState extends State<BioReplyRow> {
  /// The reaction just sent (shown picked for a moment).
  String? _sent;
  bool _sending = false;

  String get _name =>
      widget.profile.shortName.isEmpty ? 'them' : widget.profile.shortName;

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _send(String body) async {
    final messaging = MessagingScope.read(context);
    final id = widget.profile.backendId;
    if (messaging == null || id == null || _sending) return false;
    _sending = true;
    try {
      await messaging.replyToBio(id, body);
      return true;
    } on BackendException catch (error) {
      if (mounted) _say(error.message);
    } catch (_) {
      if (mounted) _say("That didn't send. Please try again.");
    } finally {
      _sending = false;
    }
    return false;
  }

  Future<void> _react(String emoji) async {
    setState(() => _sent = emoji);
    if (await _send(emoji) && mounted) _say('$emoji sent to $_name');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted && _sent == emoji) setState(() => _sent = null);
  }

  Future<void> _reply() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BioReplySheet(name: _name, bio: widget.profile.bio),
    );
    if (text == null || text.isEmpty || !mounted) return;
    if (await _send(text) && mounted) _say('Reply sent to $_name');
  }

  @override
  Widget build(BuildContext context) {
    final reactions = quickReactionsOf(context).take(4).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        key: const Key('bioText'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _react(firstReactionOf(context)),
        child: widget.bio,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          key: const Key('bioReplyRow'),
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final emoji in reactions)
              InkWell(
                key: Key('bioReact-$emoji'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => _react(emoji),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _sent == emoji
                        ? HuntrColors.orange.withValues(alpha: 0.22)
                        : HuntrColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _sent == emoji
                            ? HuntrColors.orange
                            : HuntrColors.border),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
              ),
            TextButton.icon(
              key: const Key('bioReplyButton'),
              onPressed: _reply,
              icon: const Icon(Icons.reply_rounded, size: 18),
              label: const Text('Reply'),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Writing a reply to a bio (the bio over it): its text, when sent.
class _BioReplySheet extends StatefulWidget {
  const _BioReplySheet({required this.name, required this.bio});

  final String name;
  final String bio;

  @override
  State<_BioReplySheet> createState() => _BioReplySheetState();
}

class _BioReplySheetState extends State<_BioReplySheet> {
  // lives as long as the sheet (also while it slides away)
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          key: const Key('bioReplySheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reply to ${widget.name}’s bio',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            // what they wrote, over the reply
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: HuntrColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                    left: BorderSide(color: HuntrColors.orange, width: 3)),
              ),
              child: Text(widget.bio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: HuntrColors.muted, height: 1.35)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('bioReplyInput'),
                  controller: _input,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Write a reply…'),
                  onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const Key('bioReplySend'),
                tooltip: 'Send',
                style: IconButton.styleFrom(
                  backgroundColor: HuntrColors.orange,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.send_rounded),
                onPressed: () => Navigator.of(context).pop(_input.text.trim()),
              ),
            ]),
          ],
        ),
      );
}
