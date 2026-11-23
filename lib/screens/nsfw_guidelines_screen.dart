import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/info_page.dart';

/// What is NSFW?: what counts, how to turn the warning on or off, and how
/// HUNTR handles it. Information only (opened from Settings, under Show NSFW
/// warning, and from onboarding); nothing to accept.
class NsfwGuidelinesScreen extends StatelessWidget {
  const NsfwGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) => const InfoPage(
        title: 'What is NSFW?',
        listKey: Key('nsfwGuidelines'),
        children: [
          InfoIntro(
            'NSFW means Not Safe For Work. It refers to content that may '
            'be inappropriate to view in public or professional '
            'environments.',
          ),
          SizedBox(height: 28),
          InfoHeading('What counts as NSFW'),
          SizedBox(height: 12),
          InfoCard(children: [
            InfoBullet('Nudity or sexually suggestive images'),
            InfoBullet('Explicit adult content'),
            InfoBullet('Sexually suggestive videos'),
            InfoBullet('Other content that may be inappropriate in public'),
          ]),
          SizedBox(height: 28),
          InfoHeading('How to turn it on or off'),
          SizedBox(height: 12),
          InfoCard(children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: NsfwWarningSteps(),
            ),
          ]),
          SizedBox(height: 28),
          InfoHeading('How it works on HUNTR'),
          SizedBox(height: 12),
          InfoCard(children: [
            InfoPoint(
              icon: Icons.tune_rounded,
              title: 'Your setting',
              text: 'Show NSFW warning is in Settings, Yes by default. '
                  'Yes: NSFW photos and videos in Threads stay blurred '
                  'until you tap them, and albums show a warning before '
                  'they open. No: everything appears as it is. You can '
                  'change it any time.',
            ),
            infoDivider,
            InfoPoint(
              icon: Icons.tag_rounded,
              title: 'NSFW posts',
              text: 'Posts with adult or sexually suggestive content '
                  'should have the NSFW tag (under Content when you '
                  'choose tags). Everyone sees the tag on the post.',
            ),
            infoDivider,
            InfoPoint(
              icon: Icons.photo_library_outlined,
              title: 'Private albums',
              text: 'Private albums may contain NSFW content. With Show '
                  'NSFW warning on Yes, albums show a warning first and open '
                  'only when you choose View album. Sending and trading '
                  'never ask.',
            ),
            infoDivider,
            InfoPoint(
              icon: Icons.handshake_outlined,
              title: 'Respect and consent',
              text: 'Only share private content with people who are '
                  "comfortable receiving it. Respect other people's "
                  'boundaries and privacy.',
            ),
          ]),
        ],
      );
}

/// How to turn Show NSFW warning on or off, step by step (on What is NSFW?
/// and in onboarding).
class NsfwWarningSteps extends StatelessWidget {
  const NsfwWarningSteps({super.key});

  static const _steps = [
    'Tap Me, then the Settings gear at the top.',
    'Under Content, find Show NSFW warning.',
    'Tap Yes to turn the warning on, or No to turn it off.',
  ];

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('nsfwWarningSteps'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Row(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: HuntrColors.orange,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_steps[i],
                        style: const TextStyle(fontSize: 15, height: 1.4))),
              ]),
            ),
        ],
      );
}
