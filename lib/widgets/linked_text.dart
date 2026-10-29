import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Web addresses in text: with http(s):// or www., or a bare domain like
/// web.huntr.online (with an optional path). Trailing punctuation (a full
/// stop after a link) isn't part of it.
final linkPattern = RegExp(
    r'(?:https?:\/\/|www\.)[^\s<>"]+|\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?:\/[^\s<>"]*)?',
    caseSensitive: false);

/// Where a link found in text goes (https:// added when it has no scheme).
Uri? linkTarget(String link) =>
    Uri.tryParse(link.contains('://') ? link : 'https://$link');

/// [text] split into plain parts and links: (part, isLink).
List<(String, bool)> splitLinks(String text) {
  final parts = <(String, bool)>[];
  var at = 0;
  for (final match in linkPattern.allMatches(text)) {
    var link = match[0]!;
    // a sentence's own punctuation after the link
    final trimmed = link.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
    if (match.start > at) parts.add((text.substring(at, match.start), false));
    parts.add((trimmed, true));
    if (trimmed.length < link.length) {
      parts.add((link.substring(trimmed.length), false));
    }
    at = match.end;
  }
  if (at < text.length) parts.add((text.substring(at), false));
  return parts;
}

/// Text whose web addresses are tappable (orange, underlined), opening in
/// the browser.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text,
      {super.key, this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _taps = <TapGestureRecognizer>[];

  void _forget() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _forget();
    super.dispose();
  }

  TapGestureRecognizer _open(String link) {
    final tap = TapGestureRecognizer()
      ..onTap = () {
        final target = linkTarget(link);
        if (target != null) {
          launchUrl(target, mode: LaunchMode.externalApplication);
        }
      };
    _taps.add(tap);
    return tap;
  }

  @override
  Widget build(BuildContext context) {
    _forget();
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    // the accent (orange, or the colour chosen in Appearance)
    final accent = HuntrColors.orange;
    return Text.rich(
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        TextSpan(style: style, children: [
          for (final (part, isLink) in splitLinks(widget.text))
            isLink
                ? TextSpan(
                    text: part,
                    style: TextStyle(
                        color: accent,
                        decoration: TextDecoration.underline,
                        decorationColor: accent),
                    recognizer: _open(part))
                : TextSpan(text: part),
        ]));
  }
}
