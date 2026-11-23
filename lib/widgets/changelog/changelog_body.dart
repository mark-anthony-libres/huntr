import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';
import '../nearby/nearby_media.dart' show NearbyMediaViewer;

/// A changelog entry's text, as written in the admin dashboard's editor:
/// headings, colours, sizes, lists, quotes, tables and links as they are;
/// photos full width (tap: full screen, zoomable), videos as their still
/// with a play button (tap: played full screen), YouTube videos as a card
/// that opens YouTube. [html] is the backend's (cleaned), [backendUrl] the
/// API its photos and videos are under.
class ChangelogBody extends StatelessWidget {
  const ChangelogBody(
      {super.key, required this.html, required this.backendUrl});

  final String html;
  final String backendUrl;

  static const _textStyle =
      TextStyle(fontSize: 15.5, height: 1.55, color: Color(0xEBFFFFFF));

  @override
  Widget build(BuildContext context) {
    final linked = changelogMediaLinks(html, backendUrl);
    return HtmlWidget(
      linked,
      textStyle: _textStyle,
      customStylesBuilder: _styles,
      customWidgetBuilder: (element) => switch (element.localName) {
        'img' => _picture(context, element.attributes['src']),
        'video' => _video(context, element.attributes),
        'div' when element.attributes.containsKey('data-youtube-video') =>
          _youtube(element.querySelector('iframe')?.attributes['src']),
        _ => null,
      },
      onTapUrl: (url) =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }

  static Map<String, String>? _styles(dynamic element) =>
      switch (element.localName as String?) {
        'a' => {'color': '#FF7A1A', 'font-weight': '700'},
        'h1' => {
            'font-size': '1.7em',
            'font-weight': '800',
            'margin': '0.6em 0 0.3em'
          },
        'h2' => {
            'font-size': '1.4em',
            'font-weight': '800',
            'margin': '0.6em 0 0.3em'
          },
        'h3' => {
            'font-size': '1.2em',
            'font-weight': '700',
            'margin': '0.5em 0 0.25em'
          },
        'h4' => {
            'font-size': '1.05em',
            'font-weight': '700',
            'margin': '0.5em 0 0.25em'
          },
        'p' => {'margin': '0 0 0.7em'},
        // the highlight's own colour (its style), behind light text
        'mark' => {'color': '#EBFFFFFF'},
        'blockquote' => {
            'margin': '0 0 0.7em',
            'padding': '0 0 0 12px',
            'border-left': '3px solid #FF7A1A',
            'color': '#9A9FAD',
          },
        'pre' => {
            'background-color': '#22232A',
            'padding': '10px 12px',
            'font-size': '13px',
          },
        'table' => {'border-collapse': 'collapse', 'margin': '0 0 0.7em'},
        'th' => {
            'border': '1px solid #2A2B33',
            'padding': '6px 8px',
            'background-color': '#22232A',
            'font-weight': '700',
          },
        'td' => {'border': '1px solid #2A2B33', 'padding': '6px 8px'},
        'hr' => {'margin': '1em 0'},
        _ => null,
      };

  Widget? _picture(BuildContext context, String? src) {
    if (src == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _open(
            context,
            NearbyMedia(
                id: _viewerId(src),
                isVideo: false,
                url: src,
                previewUrl: src,
                width: 0,
                height: 0)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            src,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, __, ___) => const _Missing(),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(color: HuntrColors.surface)),
          ),
        ),
      ),
    );
  }

  Widget? _video(BuildContext context, Map<Object, String> attributes) {
    final src = attributes['src'];
    if (src == null) return null;
    final poster = attributes['poster'];
    final width = int.tryParse(attributes['width'] ?? '') ?? 0;
    final height = int.tryParse(attributes['height'] ?? '') ?? 0;
    final ratio = width > 0 && height > 0 ? width / height : 16 / 9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        key: const Key('changelogVideo'),
        onTap: () => _open(
            context,
            NearbyMedia(
                id: _viewerId(src),
                isVideo: true,
                url: src,
                previewUrl: poster,
                width: width,
                height: height)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: ratio.clamp(0.5, 2.4),
            child: Stack(fit: StackFit.expand, children: [
              if (poster != null)
                Image.network(poster,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _Missing())
              else
                const ColoredBox(color: Colors.black),
              const Center(child: _PlayButton()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget? _youtube(String? src) {
    final id = src == null
        ? null
        : RegExp(r'/embed/([A-Za-z0-9_-]+)').firstMatch(src)?.group(1);
    if (id == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        key: const Key('changelogYoutube'),
        onTap: () => launchUrl(Uri.parse('https://www.youtube.com/watch?v=$id'),
            mode: LaunchMode.externalApplication),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Image.network('https://i.ytimg.com/vi/$id/hqdefault.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black)),
              const Center(child: _PlayButton(youtube: true)),
            ]),
          ),
        ),
      ),
    );
  }

  /// An id for the full-screen viewer (its video players are kept by id):
  /// one per file, never a Threads post's (theirs are positive).
  static int _viewerId(String src) => -1 - (src.hashCode & 0x3fffffff);

  void _open(BuildContext context, NearbyMedia media) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => NearbyMediaViewer(media: [media])));
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({this.youtube = false});

  final bool youtube;

  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: youtube ? const Color(0xFFFF0033) : Colors.black54,
          shape: BoxShape.circle,
          border: youtube ? null : Border.all(color: Colors.white70, width: 2),
        ),
        child:
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
      );
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) => const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: HuntrColors.surface,
          child: Center(
              child:
                  Icon(Icons.broken_image_outlined, color: HuntrColors.muted)),
        ),
      );
}
