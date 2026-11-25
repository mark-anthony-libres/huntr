import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/pill_tabs.dart';

/// How to add the guest link to a story, step by step, for My Day or
/// Instagram (Instagram's link sticker is everyone's; on Facebook not every
/// account has one: then the link goes in as text).
class GuestStoryHowToScreen extends StatefulWidget {
  const GuestStoryHowToScreen(
      {super.key, required this.url, this.sharing = false});

  final String url;

  /// Opened from Share to story: the last step shares the card (the
  /// screen closes returning true), instead of Got it.
  final bool sharing;

  @override
  State<GuestStoryHowToScreen> createState() => _GuestStoryHowToScreenState();
}

class _GuestStoryHowToScreenState extends State<GuestStoryHowToScreen> {
  bool _instagram = false;
  int _step = 0;

  static const _myDay = [
    (
      'In the share sheet, pick Facebook (My Day)',
      'The card opens in Facebook, ready to post.'
    ),
    (
      'Tap the sticker button and choose Link',
      'Not every account has it. If you don’t see Link, use the text '
          'button instead.'
    ),
    (
      'Paste your link',
      'It’s already copied from step 1. As text, people copy it from your '
          'story.'
    ),
    ('Place it on the card and post', 'People tap your link to chat.'),
  ];

  static const _ig = [
    (
      'In the share sheet, pick Instagram (Stories)',
      'The card opens in Instagram, ready to post.'
    ),
    (
      'Tap the sticker button and choose LINK',
      'Everyone on Instagram has the Link sticker.'
    ),
    ('Paste your link', 'It’s already copied from step 1.'),
    (
      'Place it on the card and post',
      'People tap the sticker to open your chat.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final steps = _instagram ? _ig : _myDay;
    final (title, detail) = steps[_step];
    final last = _step == steps.length - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Add the link to your story')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PillTabs(
                    selected: _instagram ? 1 : 0,
                    onChanged: (i) => setState(() {
                      _instagram = i == 1;
                      _step = 0;
                    }),
                    tabs: const [
                      PillTab(
                          key: Key('howToMyDay'),
                          icon: Icons.auto_stories_outlined,
                          label: 'My Day'),
                      PillTab(
                          key: Key('howToInstagram'),
                          icon: Icons.camera_alt_outlined,
                          label: 'Instagram'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        Semantics(
                          button: true,
                          label: 'Step ${i + 1}',
                          child: InkResponse(
                            onTap: () => setState(() => _step = i),
                            radius: 26,
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _step
                                    ? Colors.white
                                    : HuntrColors.surfaceHigh,
                              ),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: i == _step
                                          ? Colors.black
                                          : Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(title,
                      key: const Key('howToTitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20,
                          height: 1.35,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: HuntrColors.muted, height: 1.5)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFF7A1A), Color(0xFFC2185B)]),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(20),
                      child: _Picture(
                          step: _step, instagram: _instagram, url: widget.url),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('howToNext'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(56),
                        textStyle: const TextStyle(
                            fontFamily: huntrFontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    onPressed: () => last
                        ? Navigator.of(context).pop(widget.sharing)
                        : setState(() => _step++),
                    child: Text(last
                        ? (widget.sharing ? 'Share to story' : 'Got it')
                        : 'Next step'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each step's picture.
class _Picture extends StatelessWidget {
  const _Picture(
      {required this.step, required this.instagram, required this.url});

  final int step;
  final bool instagram;
  final String url;

  Widget _pill(String text,
          {Color color = Colors.black, bool picked = false}) =>
      Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: picked ? Border.all(color: Colors.black, width: 3) : null,
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case 0:
        Widget target(String name, Color color, bool picked) => Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border:
                    picked ? Border.all(color: Colors.black, width: 3) : null,
              ),
              child: Row(children: [
                Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(10))),
                const SizedBox(width: 14),
                Text(name,
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ]),
            );
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            target('Facebook My Day', const Color(0xFF3B82F6), !instagram),
            target('Instagram story', const Color(0xFFFF5CA8), instagram),
            target('More', const Color(0xFF2EE59D), false),
          ]),
        );
      case 1:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 2.2,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _pill('POLL', color: const Color(0xFF6D28D9)),
              _pill('#TAG', color: const Color(0xFFC2185B)),
              _pill('MUSIC'),
              _pill('GIF'),
              _pill('LINK', color: const Color(0xFF3B82F6), picked: true),
              _pill('TIME'),
            ],
          ),
        );
      case 2:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('URL',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Container(
                  height: 52,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: Text(url.replaceFirst('https://', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w600)),
                ),
              ]),
        );
      default:
        return AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 160),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1210),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              const Spacer(),
              const Text('Chat with me anonymously',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
              const Spacer(),
              _pill('HUNTR.ONLINE/G/…', color: const Color(0xFF3B82F6)),
            ]),
          ),
        );
    }
  }
}
