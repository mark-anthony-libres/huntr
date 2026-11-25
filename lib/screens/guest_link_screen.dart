import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../flows/chat_attachments.dart' show ChatMediaPicker;
import '../services/save_image.dart';
import '../state/guest_chats_state.dart';
import '../theme.dart';
import '../widgets/anonymous_avatar.dart';
import '../widgets/photos/viewer_controls.dart' show SwipeAnyDevice;
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

  /// My own words (the last card) and picture (instead of a colour).
  String _ownWords = '';
  Uint8List? _photo;
  bool get _onOwnWords => _prompt == guestStoryPrompts.length;

  /// What the card at [i] says.
  String _words(int i) => i < guestStoryPrompts.length
      ? guestStoryPrompts[i]
      : _ownWords.isEmpty
          ? 'Write your own'
          : _ownWords;

  Future<void> _writeOwn() async {
    final input = TextEditingController(text: _ownWords);
    final words = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your words'),
        content: TextField(
          key: const Key('guestStoryOwnWords'),
          controller: input,
          autofocus: true,
          maxLength: 60,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Tell me a secret'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(input.text.trim()),
              child: const Text('Done')),
        ],
      ),
    );
    input.dispose();
    if (words != null && mounted) setState(() => _ownWords = words);
  }

  /// A picture from the device for the card (it stays on the device: only
  /// the shared image has it).
  Future<void> _pickPhoto() async {
    if (_photo != null && _look < 0) {
      // already showing it: change it or go back to colours
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose another picture'),
              onTap: () => Navigator.of(context).pop('change'),
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Remove the picture'),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ]),
        ),
      );
      if (choice == 'remove') {
        setState(() {
          _photo = null;
          _look = 0;
        });
      }
      if (choice != 'change') return;
    } else if (_photo != null) {
      setState(() => _look = -1);
      return;
    }
    final picked = await ChatMediaPicker.instance.pickImage();
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) {
      setState(() {
        _photo = bytes;
        _look = -1;
      });
    }
  }

  /// The story cards, swiped for other words.
  PageController? _pages;
  static const _cardWidth = 236.0;
  int _look = 0;
  bool _loading = true;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
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
    if (_onOwnWords && _ownWords.isEmpty) {
      await _writeOwn();
      if (_ownWords.isEmpty) return;
    }
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
                        // swipe the card for other words (the next one
                        // peeks at the side)
                        LayoutBuilder(builder: (context, box) {
                          _pages ??= PageController(
                              viewportFraction:
                                  ((_cardWidth + 24) / box.maxWidth)
                                      .clamp(0.3, 1.0));
                          return SizedBox(
                            height: _cardWidth * 16 / 9,
                            child: SwipeAnyDevice(
                              child: PageView.builder(
                                key: const Key('guestStoryCards'),
                                controller: _pages,
                                itemCount: guestStoryPrompts.length + 1,
                                onPageChanged: (i) =>
                                    setState(() => _prompt = i),
                                itemBuilder: (_, i) => Center(
                                  child: GestureDetector(
                                    // my own words: tap to write them
                                    onTap: i == guestStoryPrompts.length
                                        ? _writeOwn
                                        : null,
                                    child: SizedBox(
                                      width: _cardWidth,
                                      // the one shown is the one shared
                                      child: RepaintBoundary(
                                        key: i == _prompt ? _card : null,
                                        child: GuestStoryCard(
                                          animal: link.avatar,
                                          prompt: _words(i),
                                          colors: guestStoryLooks[
                                              _look < 0 ? 0 : _look],
                                          photo: _look < 0 && _photo != null
                                              ? MemoryImage(_photo!)
                                              : null,
                                          url: url,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i <= guestStoryPrompts.length; i++)
                              GestureDetector(
                                onTap: () => _pages?.animateToPage(i,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  width: i == _prompt ? 22 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: i == _prompt
                                        ? HuntrColors.orange
                                        : HuntrColors.border,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _onOwnWords
                            ? Center(
                                child: TextButton.icon(
                                  key: const Key('guestStoryEditWords'),
                                  onPressed: _writeOwn,
                                  icon:
                                      const Icon(Icons.edit_rounded, size: 18),
                                  label: Text(_ownWords.isEmpty
                                      ? 'Write your own words'
                                      : 'Change your words'),
                                ),
                              )
                            : const Text('Swipe the card for other words',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: HuntrColors.muted, fontSize: 13)),
                        const SizedBox(height: 28),
                        const _Label('BACKGROUND'),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _PhotoSwatch(
                              photo: _photo,
                              selected: _look < 0,
                              onTap: _pickPhoto,
                            ),
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
    this.photo,
  });

  final String animal;
  final String prompt;
  final List<Color> colors;
  final String url;

  /// A picture of my own behind it (darkened so the words stay readable),
  /// instead of [colors].
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            image: photo == null
                ? null
                : DecorationImage(
                    image: photo!,
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.38),
                        BlendMode.darken)),
            gradient: photo != null
                ? null
                : LinearGradient(
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

/// The first background: a picture of mine (a + until one is chosen).
class _PhotoSwatch extends StatelessWidget {
  const _PhotoSwatch(
      {required this.photo, required this.selected, required this.onTap});

  final Uint8List? photo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: photo == null ? 'Use a picture' : 'Your picture',
        child: GestureDetector(
          key: const Key('guestStoryPhoto'),
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HuntrColors.surfaceHigh,
              image: photo == null
                  ? null
                  : DecorationImage(
                      image: MemoryImage(photo!), fit: BoxFit.cover),
              border: Border.all(
                  color: selected ? Colors.white : HuntrColors.border,
                  width: selected ? 3 : 1),
            ),
            child: photo == null
                ? Icon(Icons.add_photo_alternate_outlined,
                    color: HuntrColors.orange)
                : null,
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
