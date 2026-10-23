import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';
import '../taps/tap_answers.dart';

/// The tap a chat started from, first in the conversation: who tapped whom
/// (and any answers, on taps sent while Tap had questions).
class TapCard extends StatelessWidget {
  const TapCard(
      {super.key,
      required this.answers,
      required this.fromMe,
      required this.otherName});

  final List<TapAnswer> answers;

  /// I'm the one who tapped.
  final bool fromMe;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    final who = otherName.isEmpty ? 'them' : otherName;
    return Center(
      child: Container(
        key: const Key('tapCard'),
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.waving_hand_rounded,
                  size: 20, color: HuntrColors.orange),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  fromMe
                      ? 'You tapped $who 👋'
                      : '${otherName.isEmpty ? 'They' : otherName} tapped you 👋',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ]),
            if (answers.isNotEmpty) ...[
              const SizedBox(height: 12),
              TapAnswers(answers: answers, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}
