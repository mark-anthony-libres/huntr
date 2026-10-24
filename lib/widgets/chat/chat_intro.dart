import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../avatar.dart';

class ChatIntro extends StatelessWidget {
  const ChatIntro({super.key, required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Avatar(profile: profile, size: 88),
          const SizedBox(height: 14),
          Text('Say hi to ${profile.name} 👋',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          // friendly, no pressure: what they're open to, when they said
          Text(
            _nudge(profile),
            key: const Key('chatIntroNudge'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted, height: 1.4),
          ),
        ]),
      ),
    );
  }
}

/// A gentle opener: what they're here for (when they said), and that a
/// simple hello is enough.
String _nudge(Profile profile) {
  final open = [
    for (final l in LookingFor.values)
      if (profile.lookingFor.contains(l)) l.label.toLowerCase()
  ].take(2).toList();
  return open.isEmpty
      ? 'No pressure. A simple hello is a great way to start, or tap one '
          'of the quick replies below.'
      : "They're open to ${open.join(' and ')}. A simple hello is a great "
          'way to start.';
}
