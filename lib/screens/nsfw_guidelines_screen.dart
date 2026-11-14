import 'package:flutter/material.dart';

import '../theme.dart';

/// What is NSFW?: what counts, how to turn the warning on or off, and how
/// HUNTR handles it. Information only (opened from Settings, under Show NSFW
/// warning, and from onboarding); nothing to accept.
class NsfwGuidelinesScreen extends StatelessWidget {
  const NsfwGuidelinesScreen({super.key});

  static const _maxWidth = 720.0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('What is NSFW?')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: ListView(
              key: const Key('nsfwGuidelines'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Text(
                  'NSFW means Not Safe For Work. It refers to content that may '
                  'be inappropriate to view in public or professional '
                  'environments.',
                  style: TextStyle(fontSize: 16, height: 1.45),
                ),
                const SizedBox(height: 28),
                const _Heading('What counts as NSFW'),
                const SizedBox(height: 12),
                const _Card(children: [
                  _Bullet('Nudity or sexually suggestive images'),
                  _Bullet('Explicit adult content'),
                  _Bullet('Sexually suggestive videos'),
                  _Bullet('Other content that may be inappropriate in public'),
                ]),
                const SizedBox(height: 28),
                const _Heading('How to turn it on or off'),
                const SizedBox(height: 12),
                const _Card(children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: NsfwWarningSteps(),
                  ),
                ]),
                const SizedBox(height: 28),
                const _Heading('How it works on HUNTR'),
                const SizedBox(height: 12),
                _Card(children: [
                  _Point(
                    icon: Icons.tune_rounded,
                    title: 'Your setting',
                    text: 'Show NSFW warning is in Settings, Yes by default. '
                        'Yes: NSFW photos and videos in Threads stay blurred '
                        'until you tap them, and albums show a warning before '
                        'they open. No: everything appears as it is. You can '
                        'change it any time.',
                  ),
                  _divider,
                  const _Point(
                    icon: Icons.tag_rounded,
                    title: 'NSFW posts',
                    text: 'Posts with adult or sexually suggestive content '
                        'should have the NSFW tag (under Content when you '
                        'choose tags). Everyone sees the tag on the post.',
                  ),
                  _divider,
                  const _Point(
                    icon: Icons.photo_library_outlined,
                    title: 'Private albums',
                    text: 'Private albums may contain NSFW content. With Show '
                        'NSFW warning on Yes, albums show a warning first and open only when you '
                        'choose View album. Sending and trading never ask.',
                  ),
                  _divider,
                  const _Point(
                    icon: Icons.handshake_outlined,
                    title: 'Respect and consent',
                    text: 'Only share private content with people who are '
                        "comfortable receiving it. Respect other people's "
                        'boundaries and privacy.',
                  ),
                ]),
              ],
            ),
          ),
        ),
      );

  static const _divider =
      Divider(height: 1, thickness: 1, color: HuntrColors.border);
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.border),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: HuntrColors.orange, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 15, height: 1.4))),
        ]),
      );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: HuntrColors.orange, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(text,
                      style: const TextStyle(
                          color: HuntrColors.muted,
                          fontSize: 14,
                          height: 1.45)),
                ]),
          ),
        ]),
      );
}
