import 'package:flutter/material.dart';

import '../theme.dart';
import 'emoticons.dart';

/// The reply box under someone's story or full-screen profile photo: a
/// message field, and beside it the quick reactions, or Send once
/// something is typed (Enter sends too). Keys: `${keyPrefix}Reply`,
/// `${keyPrefix}Send` and `${keyPrefix}React-<emoji>`.
class ReplyBar extends StatelessWidget {
  const ReplyBar(
      {super.key,
      required this.controller,
      required this.focusNode,
      required this.reactions,
      required this.onSend,
      required this.keyPrefix});

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> reactions;

  /// What was typed, or a reaction's emoji.
  final void Function(String text) onSend;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: TextField(
            key: Key('${keyPrefix}Reply'),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.send,
            inputFormatters: const [EmoticonFormatter()],
            onSubmitted: (text) => onSend(replaceEmoticons(text)),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Message…',
              hintStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: Colors.white38),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: HuntrColors.orange),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // typing: a send button; otherwise the quick reactions
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.trim().isEmpty
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final emoji in reactions)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: IconButton(
                        key: Key('${keyPrefix}React-$emoji'),
                        tooltip: 'React $emoji',
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: () => onSend(emoji),
                        icon: Text(emoji, style: const TextStyle(fontSize: 30)),
                      ),
                    ),
                ])
              : Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton.filled(
                    key: Key('${keyPrefix}Send'),
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                        backgroundColor: HuntrColors.orange,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(48, 48)),
                    onPressed: () => onSend(replaceEmoticons(controller.text)),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ),
        ),
      ]);
}
