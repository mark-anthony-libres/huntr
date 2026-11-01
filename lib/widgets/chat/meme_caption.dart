import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../theme.dart';
import 'sticker_image.dart';

/// A caption colour from the server (#RRGGBB; white when it isn't one).
Color memeColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null || hex.length != 7
      ? Colors.white
      : Color(0xFF000000 | value);
}

/// Black around a light caption, white around a dark one (as the server).
Color _outlineFor(Color color) =>
    0.299 * color.r * 255 + 0.587 * color.g * 255 + 0.114 * color.b * 255 >= 90
        ? Colors.black
        : Colors.white;

/// How tall the letters are, as a share of the picture, by the caption's
/// length: big for a few words, smaller the longer it is - the same steps
/// as the server's (sticker_meme.SIZE_BY_LENGTH) and the admin's preview.
double memeSizeShare(String text) {
  final length = text.trim().length;
  for (final (longest, share) in const [
    (10, 0.15),
    (20, 0.11),
    (30, 0.085),
    (45, 0.07),
    (70, 0.058),
  ]) {
    if (length <= longest) return share;
  }
  return 0.05;
}

/// A meme's caption over a sticker, like the server draws it on the meme:
/// bold letters in the sticker's colour with an outline, centred at the
/// bottom, wrapped onto up to three lines (a long word broken where it
/// must), as big as fits.
class MemeText extends StatelessWidget {
  const MemeText(this.text, {super.key, this.color = Colors.white});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final size = (box.maxHeight.isFinite ? box.maxHeight : box.maxWidth) *
          memeSizeShare(text);
      TextStyle style(Paint? outline) => TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: outline == null ? color : null,
            foreground: outline,
          );
      Widget line(Paint? outline) => Text(text,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: style(outline));
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(box.maxWidth * 0.04, 0,
              box.maxWidth * 0.04, box.maxHeight * 0.05),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth * 0.92,
              // centred, like the server draws it (a Stack starts its
              // children at the top left)
              child: Stack(alignment: Alignment.bottomCenter, children: [
                line(Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = size / 5.5
                  ..strokeJoin = StrokeJoin.round
                  ..color = _outlineFor(color)),
                line(null),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/// Before sending a meme sticker: an optional caption, shown on it as it's
/// typed. The caption ('' for none: the sticker as it is), or null when
/// cancelled.
Future<String?> askMemeCaption(BuildContext context, HuntrSticker sticker) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _MemeCaptionSheet(sticker: sticker),
    );

class _MemeCaptionSheet extends StatefulWidget {
  const _MemeCaptionSheet({required this.sticker});

  final HuntrSticker sticker;

  @override
  State<_MemeCaptionSheet> createState() => _MemeCaptionSheetState();
}

class _MemeCaptionSheetState extends State<_MemeCaptionSheet> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sticker = widget.sticker;
    return Padding(
      // above the keyboard
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Add a caption',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text("Optional: it's added to the sticker when you send it.",
                textAlign: TextAlign.center,
                style: TextStyle(color: HuntrColors.muted)),
            const SizedBox(height: 16),
            // the sticker, with the caption as it's typed
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.square(
                dimension: 220,
                child: Stack(fit: StackFit.expand, children: [
                  StickerImage(url: sticker.imageUrl, name: sticker.name),
                  ValueListenableBuilder(
                    valueListenable: _caption,
                    builder: (context, value, _) => MemeText(value.text,
                        key: const Key('memePreview'),
                        color: memeColor(sticker.captionColor)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('memeCaption'),
              controller: _caption,
              autofocus: true,
              maxLength: sticker.captionMaxLength,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.send,
              onSubmitted: (text) => Navigator.of(context).pop(text.trim()),
              decoration:
                  const InputDecoration(hintText: 'e.g. WAIT AND SEE ???'),
            ),
            const SizedBox(height: 8),
            // the caption is optional: empty sends the sticker as it is
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('memeSend'),
                // like the chat's own Send: dark on the accent
                style: FilledButton.styleFrom(
                    backgroundColor: HuntrColors.orange,
                    foregroundColor: Colors.black),
                onPressed: () =>
                    Navigator.of(context).pop(_caption.text.trim()),
                child: const Text('Send'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
