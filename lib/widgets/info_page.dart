import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// An information screen (What is NSFW?, About profile photos, About
/// albums): [title] in the bar, then [children] in a centred column.
class InfoPage extends StatelessWidget {
  const InfoPage(
      {super.key,
      required this.title,
      required this.listKey,
      required this.children});

  final String title;
  final Key listKey;
  final List<Widget> children;

  static const _maxWidth = 720.0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: ListView(
              key: listKey,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: children,
            ),
          ),
        ),
      );
}

/// The opening paragraph of an [InfoPage].
class InfoIntro extends StatelessWidget {
  const InfoIntro(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 16, height: 1.45));
}

class InfoHeading extends StatelessWidget {
  const InfoHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));
}

/// A rounded card of [InfoBullet]s or [InfoPoint]s (with [infoDivider]
/// between points).
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.children});

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
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

const infoDivider = Divider(height: 1, thickness: 1, color: HuntrColors.border);

class InfoBullet extends StatelessWidget {
  const InfoBullet(this.text, {super.key});

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

class InfoPoint extends StatelessWidget {
  const InfoPoint(
      {super.key, required this.icon, required this.title, required this.text});

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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(text,
                  style: const TextStyle(
                      color: HuntrColors.muted, fontSize: 14, height: 1.45)),
            ]),
          ),
        ]),
      );
}

/// The Community Guidelines on web.huntr.online ([section] is a heading's
/// anchor there).
Uri communityGuidelines({String? section}) => Uri.parse(
    'https://web.huntr.online/guidelines${section == null ? '' : '#$section'}');

/// A button that opens [url] in the browser, at the end of an [InfoPage].
class InfoLinkButton extends StatelessWidget {
  const InfoLinkButton({super.key, required this.label, required this.url});

  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: HuntrColors.orange,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            textStyle: const TextStyle(
                fontFamily: huntrFontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
          onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(label),
        ),
      );
}

/// A small ⓘ beside a section's heading that opens its information screen.
class InfoIconButton extends StatelessWidget {
  const InfoIconButton(
      {super.key, required this.tooltip, required this.screen});

  final String tooltip;
  final Widget Function() screen;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        iconSize: 18,
        color: HuntrColors.muted,
        icon: const Icon(Icons.info_outline_rounded),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen())),
      );
}
