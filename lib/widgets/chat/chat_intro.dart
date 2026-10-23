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
          Text('Say hi to ${profile.name}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'You both like ${profile.interests.take(2).join(' and ').toLowerCase()}. Start there!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted),
          ),
        ]),
      ),
    );
  }
}
