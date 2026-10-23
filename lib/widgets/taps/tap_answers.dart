import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// A tap's questions, each with its answer (or that it was skipped).
class TapAnswers extends StatelessWidget {
  const TapAnswers({super.key, required this.answers, this.compact = false});

  final List<TapAnswer> answers;

  /// Smaller text and spacing (inside a chat bubble).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, a) in answers.indexed) ...[
          if (i > 0) SizedBox(height: compact ? 10 : 16),
          Text(a.question,
              style: TextStyle(
                  color: HuntrColors.muted,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3)),
          const SizedBox(height: 4),
          Text(
            a.answer ?? 'Skipped',
            style: TextStyle(
                fontSize: compact ? 15 : 16,
                height: 1.35,
                fontStyle: a.answer == null ? FontStyle.italic : null,
                color: a.answer == null ? HuntrColors.muted : null),
          ),
        ],
      ],
    );
  }
}
