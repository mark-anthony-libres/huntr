import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/save_image.dart';
import '../state/guest_chats_state.dart';
import '../theme.dart';
import '../widgets/anonymous_avatar.dart';
import 'guest_story_how_to_screen.dart';

/// The words a story card can say.
const guestStoryPrompts = [
  'Chat with me anonymously',
  'Ask me anything',
  'Say hi, no names',
];

/// The story card's colours.
const guestStoryLooks = [
  [Color(0xFFFF7A1A), Color(0xFFC2185B)],
  [Color(0xFF3A2418), Color(0xFF111114)],
  [Color(0xFF3B82F6), Color(0xFF1E3A8A)],
  [Color(0xFF2EE59D), Color(0xFF0F766E)],
  [Color(0xFFFF5CA8), Color(0xFF6D28D9)],
];

/// My guest link: a story card to post on My Day or a story (its words and
/// colour mine to pick), then 1. copy the link, 2. share the card (the
/// phone's share sheet; the link is copied too, for the link sticker).
class GuestLinkScreen extends StatefulWidget {
  const GuestLinkScreen({super.key});

  @override
  State<GuestLinkScreen> createState() => _GuestLinkScreenState();
}

class _GuestLinkScreenState extends State<GuestLinkScreen> {
  final _card = GlobalKey();
  int _prompt = 0;
  int _look = 0;
  bool _loading = true;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = GuestChatsScope.read(context);
    if (state == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var link = await state.loadLink();
      // the first time: a link is made for me
      if (link != null && link.code == null) link = await state.newLink();
    } catch (_) {
      _error = "Your guest link couldn't load. Check your connection.";
    }
    if (mounted) setState(() => _loading = false);
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _copy(String url, {bool quiet = false}) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!quiet && mounted) _say('Link copied');
  }

  /// The card as a 1080 x 1920 picture.
  Future<Uint8List?> _picture() async {
    final boundary =
        _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image =
        await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _share(String url) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _copy(url, quiet: true);
      final png = await _picture();
      if (png == null) return;
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(png,
              mimeType: 'image/png', name: 'huntr-guest-link.png')
        ],
        fileNameOverrides: const ['huntr-guest-link.png'],
      ));
      if (mounted) _say('Your link is copied. Add it with the link sticker.');
    } catch (_) {
      if (mounted) _say("Couldn't open sharing. Try Save image instead.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _save() async {
    final png = await _picture();
    if (png == null) return;
    try {
      await saveImage(png, 'huntr-guest-link.png');
    } catch (_) {
      if (mounted) _say("The image couldn't be saved. Please try again.");
    }
  }

  Future<void> _menu(String choice, GuestChatsState state) async {
    if (choice == 'new') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Make a new link?'),
          content: const Text(
              'Your current link stops working, and chats from it end.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('New link')),
          ],
        ),
      );
      if (sure == true) {
        await state.newLink();
        if (mounted) _say('You have a new link');
      }
    } else {
      await state.setLinkOn(choice == 'on');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = GuestChatsScope.of(context);
    final link = state?.link;
    final url = link?.url;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest link'),
        actions: [
          if (state != null && link?.code != null)
            PopupMenuButton<String>(
              key: const Key('guestLinkMenu'),
              tooltip: 'More',
              onSelected: (choice) => _menu(choice, state),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new', child: Text('New link')),
                PopupMenuItem(
                    value: link!.isOn ? 'off' : 'on',
                    child: Text(link.isOn
                        ? 'Turn off guest link'
                        : 'Turn on guest link')),
              ],
            ),
        ],
      ),
      body: _loading && link == null
          ? const Center(child: CircularProgressIndicator())
          : link == null || url == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error ?? "Your guest link couldn't load.",
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      key: const Key('guestLinkScreen'),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                      children: [
                        const Text(
                            'Post this on your My Day or story. People tap '
                            'your link and chat with you anonymously, no '
                            'account needed.',
                            style: TextStyle(
                                color: HuntrColors.muted,
                                fontSize: 14.5,
                                height: 1.5)),
                        if (!link.isOn) ...[
                          const SizedBox(height: 16),
                          _OffNotice(onTurnOn: () => state!.setLinkOn(true)),
                        ],
                        const SizedBox(height: 24),
                        Center(
                          child: SizedBox(
                            width: 236,
                            child: RepaintBoundary(
                              key: _card,
                              child: GuestStoryCard(
                                animal: link.avatar,
                                prompt: guestStoryPrompts[_prompt],
                                colors: guestStoryLooks[_look],
                                url: url,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const _Label('WHAT IT SAYS'),
                        const SizedBox(height: 12),
                        for (var i = 0; i < guestStoryPrompts.length; i++) ...[
                          _Choice(
                            text: guestStoryPrompts[i],
                            selected: i == _prompt,
                            onTap: () => setState(() => _prompt = i),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 18),
                        const _Label('COLOUR'),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var i = 0; i < guestStoryLooks.length; i++)
                              _Swatch(
                                colors: guestStoryLooks[i],
                                selected: i == _look,
                                onTap: () => setState(() => _look = i),
                              ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        _Step(
                          number: 1,
                          title: 'Copy your link',
                          child: _LinkField(url: url, onCopy: () => _copy(url)),
                        ),
                        const SizedBox(height: 28),
                        _Step(
                          number: 2,
                          title: 'Post it on your story',
                          detail: 'Pick My Day or Instagram, then add the '
                              'link sticker. Your link is already copied.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DecoratedBox(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Color(0xFFFF5CA8),
                                    Color(0xFFFF7A1A)
                                  ]),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(28)),
                                ),
                                child: FilledButton.icon(
                                  key: const Key('shareGuestLink'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.black,
                                    minimumSize: const Size.fromHeight(56),
                                    textStyle: const TextStyle(
                                        fontFamily: huntrFontFamily,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  onPressed:
                                      _sharing ? null : () => _share(url),
                                  icon: _sharing
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.black))
                                      : const Icon(Icons.ios_share_rounded),
                                  label: const Text('Share to story'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    key: const Key('saveGuestStory'),
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(48),
                                        shape: const StadiumBorder()),
                                    onPressed: _save,
                                    icon: const Icon(Icons.download_rounded,
                                        size: 18),
                                    label: const Text('Save image'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    key: const Key('guestStoryHowTo'),
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(48),
                                        shape: const StadiumBorder()),
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                GuestStoryHowToScreen(
                                                    url: url))),
                                    icon: const Icon(Icons.help_outline_rounded,
                                        size: 18),
                                    label: const Text('How to'),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

/// The picture posted to a story (9:16): HUNTR at the top, my animal and the
/// words in the middle, room for the link sticker, and the link in print
/// (for stories without a link sticker).
class GuestStoryCard extends StatelessWidget {
  const GuestStoryCard({
    super.key,
    required this.animal,
    required this.prompt,
    required this.colors,
    required this.url,
  });

  final String animal;
  final String prompt;
  final List<Color> colors;
  final String url;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors),
          ),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          child: Column(children: [
            const Text('HUNTR',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: AnonymousArt(
                  animal: animal, radius: 48, size: 90, ring: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(prompt,
                key: const Key('guestStoryPrompt'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 10)])),
            const Spacer(),
            Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
              child: const Text('Link sticker goes here',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Text(url.replaceFirst('https://', ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: HuntrColors.muted,
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800));
}

class _Choice extends StatelessWidget {
  const _Choice(
      {required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected
            ? HuntrColors.orange.withValues(alpha: 0.12)
            : HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? HuntrColors.orange : HuntrColors.border,
              width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected ? HuntrColors.orange : Colors.white)),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: HuntrColors.orange),
            ]),
          ),
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.colors, required this.selected, required this.onTap});

  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Colour',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors),
              border: Border.all(
                  color: selected ? Colors.white : HuntrColors.border,
                  width: selected ? 3 : 1),
            ),
          ),
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.number,
      required this.title,
      required this.child,
      this.detail});

  final int number;
  final String title;
  final String? detail;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: HuntrColors.orange, shape: BoxShape.circle),
            child: Text('$number',
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 6),
                  Text(detail!,
                      style: const TextStyle(
                          color: HuntrColors.muted,
                          fontSize: 13.5,
                          height: 1.5)),
                ],
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ],
      );
}

class _LinkField extends StatelessWidget {
  const _LinkField({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(children: [
          Expanded(
            child: Text(url.replaceFirst('https://', ''),
                key: const Key('guestLinkUrl'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            key: const Key('copyGuestLink'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
          ),
        ]),
      );
}

class _OffNotice extends StatelessWidget {
  const _OffNotice({required this.onTurnOn});

  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(children: [
          const Expanded(
            child: Text('Your guest link is off. Nobody can start a chat '
                'from it.'),
          ),
          TextButton(onPressed: onTurnOn, child: const Text('Turn on')),
        ]),
      );
}
