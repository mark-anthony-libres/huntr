import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../flows/chat_attachments.dart' show ChatMediaPicker;
import '../services/save_image.dart';
import '../services/story_share.dart';
import '../services/guest_chat_api.dart' show ReadyStoryGroup;
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

  /// The ready-made cards (finished pictures) instead of my own, and the
  /// one shown.
  bool _readyMade = false;
  int _ready = 0;

  /// The group of ready-made cards shown (its id; null: the first).
  int? _readyGroup;
  PageController? _readyPages;
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
    _readyPages?.dispose();
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
      unawaited(state.loadReadyCards());
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

  /// Share to story: how to add the link (My Day or Instagram), then the
  /// last step shares the card through the phone's share sheet.
  Future<void> _stepsThenShare(String url) async {
    if (!_readyMade && _onOwnWords && _ownWords.isEmpty) {
      await _writeOwn();
      if (_ownWords.isEmpty || !mounted) return;
    }
    final app = await Navigator.of(context).push<StoryApp>(MaterialPageRoute(
        builder: (_) => GuestStoryHowToScreen(url: url, sharing: true)));
    if (app != null && mounted) await _share(url, app);
  }

  /// The card to [app]'s story editor (the phone app: Instagram or
  /// Facebook, whichever is there), else the share sheet; the link copied
  /// either way, for the link sticker.
  Future<void> _share(String url, StoryApp app) async {
    if (_sharing) return;
    if (!_readyMade && _onOwnWords && _ownWords.isEmpty) {
      await _writeOwn();
      if (_ownWords.isEmpty) return;
    }
    setState(() => _sharing = true);
    try {
      await _copy(url, quiet: true);
      final png = await _picture();
      if (png == null) return;
      if (await StoryShare.open(png, first: app)) {
        if (mounted) _say('Your link is copied. Add it with the link sticker.');
        return;
      }
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

  /// The ready-made cards across the width, swiped for the next (the one
  /// shown is the one shared), and where I am among them.
  Widget _readyStrip(List<ReadyStoryGroup>? loaded) {
    // (a group with no cards shows nothing)
    final groups = loaded?.where((g) => g.cards.isNotEmpty).toList();
    if (groups == null) {
      return SizedBox(
          height: _cardWidth * 16 / 9,
          child: const Center(child: CircularProgressIndicator()));
    }
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
            child: Text('No ready-made cards yet.',
                style: TextStyle(color: HuntrColors.muted))),
      );
    }
    final group = groups.firstWhere((g) => g.id == _readyGroup,
        orElse: () => groups.first);
    final cards = group.cards;
    final shown = _ready.clamp(0, cards.length - 1);
    return Column(children: [
      // the groups (e.g. Cute, Pets, Bold): one at a time
      if (groups.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      key: Key('guestReadyGroup-${g.id}'),
                      label: Text(g.name),
                      selected: g.id == group.id,
                      showCheckmark: false,
                      onSelected: (_) {
                        if (g.id == group.id) return;
                        setState(() {
                          _readyGroup = g.id;
                          _ready = 0;
                        });
                        if (_readyPages?.hasClients ?? false) {
                          _readyPages!.jumpToPage(0);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth.clamp(0.0, 720.0);
        _readyPages ??= PageController(
            viewportFraction: ((_cardWidth + 28) / width).clamp(0.3, 1.0));
        return Center(
          child: SizedBox(
            width: width,
            height: _cardWidth * 16 / 9,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, 0.06, 0.94, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: SwipeAnyDevice(
                child: PageView.builder(
                  key: ValueKey('guestReadyCards-${group.id}'),
                  controller: _readyPages,
                  itemCount: cards.length,
                  onPageChanged: (i) => setState(() => _ready = i),
                  itemBuilder: (_, i) => Center(
                    child: SizedBox(
                      width: _cardWidth,
                      height: _cardWidth * 16 / 9,
                      // the one shown is the one shared
                      child: RepaintBoundary(
                        key: i == shown ? _card : null,
                        child: Image.network(
                          cards[i].url,
                          key: Key('guestReadyCard-${cards[i].id}'),
                          fit: BoxFit.cover,
                          semanticLabel: cards[i].name,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : const ColoredBox(
                                      color: HuntrColors.surface,
                                      child: Center(
                                          child: CircularProgressIndicator())),
                          errorBuilder: (context, error, stack) =>
                              const ColoredBox(
                                  color: HuntrColors.surface,
                                  child: Center(
                                      child: Icon(Icons.broken_image_outlined,
                                          color: HuntrColors.muted))),
                        ),
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
      Text('${shown + 1} of ${cards.length} · Swipe for more designs',
          key: const Key('guestReadyCount'),
          style: const TextStyle(color: HuntrColors.muted, fontSize: 13)),
    ]);
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
              : ListView(
                  key: const Key('guestLinkScreen'),
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 48),
                  children: [
                    _Column(
                      child: const Text(
                          'Post this on your My Day or story. People tap '
                          'your link and chat with you anonymously, no '
                          'account needed.',
                          style: TextStyle(
                              color: HuntrColors.muted,
                              fontSize: 14.5,
                              height: 1.5)),
                    ),
                    if (!link.isOn)
                      _Column(
                        top: 16,
                        child:
                            _OffNotice(onTurnOn: () => state!.setLinkOn(true)),
                      ),
                    const SizedBox(height: 20),
                    // my own card (words and background), or a ready-made one:
                    // two small chips (like the groups under them)
                    Center(
                      child: Wrap(spacing: 8, children: [
                        for (final (ready, icon, label, key) in const [
                          (
                            false,
                            Icons.edit_rounded,
                            'Your own',
                            'guestStoryOwnTab'
                          ),
                          (
                            true,
                            Icons.auto_awesome_rounded,
                            'Ready-made',
                            'guestStoryReadyTab'
                          ),
                        ])
                          ChoiceChip(
                            key: Key(key),
                            avatar: Icon(icon,
                                size: 16,
                                color: _readyMade == ready
                                    ? Colors.black
                                    : HuntrColors.muted),
                            label: Text(label),
                            selected: _readyMade == ready,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _readyMade = ready),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    if (_readyMade)
                      _readyStrip(state?.readyCards)
                    else ...[
                      // the cards across the whole width: swipe for other
                      // words, the next one peeking at the side
                      LayoutBuilder(builder: (context, box) {
                        final width = box.maxWidth.clamp(0.0, 720.0);
                        _pages ??= PageController(
                            viewportFraction:
                                ((_cardWidth + 28) / width).clamp(0.3, 1.0));
                        return Center(
                          child: SizedBox(
                            width: width,
                            height: _cardWidth * 16 / 9,
                            // the cards fade out at the strip's ends
                            child: ShaderMask(
                              shaderCallback: (rect) => const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black,
                                  Colors.black,
                                  Colors.transparent,
                                ],
                                stops: [0, 0.06, 0.94, 1],
                              ).createShader(rect),
                              blendMode: BlendMode.dstIn,
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
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 6),
                      Center(
                        child: _onOwnWords
                            ? TextButton.icon(
                                key: const Key('guestStoryEditWords'),
                                onPressed: _writeOwn,
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                label: Text(_ownWords.isEmpty
                                    ? 'Write your own words'
                                    : 'Change your words'),
                              )
                            : const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('Swipe the card for other words',
                                    style: TextStyle(
                                        color: HuntrColors.muted,
                                        fontSize: 13)),
                              ),
                      ),
                    ],
                    // ---- its background (my own card's) ----
                    if (!_readyMade)
                      _Column(
                        top: 24,
                        child: _Panel(
                          icon: Icons.palette_outlined,
                          title: 'Background',
                          child: LayoutBuilder(builder: (context, box) {
                            // six on one line: as big as fits, up to 52
                            final size =
                                ((box.maxWidth - 5 * 12) / 6).clamp(36.0, 52.0);
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _PhotoSwatch(
                                  size: size,
                                  photo: _photo,
                                  selected: _look < 0,
                                  onTap: _pickPhoto,
                                ),
                                for (var i = 0; i < guestStoryLooks.length; i++)
                                  _Swatch(
                                    size: size,
                                    colors: guestStoryLooks[i],
                                    selected: i == _look,
                                    onTap: () => setState(() => _look = i),
                                  ),
                              ],
                            );
                          }),
                        ),
                      ),
                    // ---- sharing it ----
                    _Column(
                      top: 16,
                      child: _Panel(
                        icon: Icons.ios_share_rounded,
                        title: 'Share your link',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Step(
                              number: 1,
                              title: 'Copy your link',
                              child: _LinkField(
                                  url: url, onCopy: () => _copy(url)),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child:
                                  Divider(height: 1, color: HuntrColors.border),
                            ),
                            _Step(
                                number: 2,
                                title: 'Post it on your story',
                                detail:
                                    'Pick My Day or Instagram, then add the '
                                    'link sticker. Your link is copied for you.'),
                            const SizedBox(height: 16),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: HuntrColors.accentGradient,
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(28)),
                              ),
                              child: FilledButton.icon(
                                key: const Key('shareGuestLink'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size.fromHeight(56),
                                  textStyle: const TextStyle(
                                      fontFamily: huntrFontFamily,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800),
                                ),
                                // the steps first, then the share sheet
                                onPressed: _sharing
                                    ? null
                                    : () => _stepsThenShare(url),
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
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: _SecondaryButton(
                                  key: const Key('saveGuestStory'),
                                  icon: Icons.download_rounded,
                                  label: 'Save image',
                                  onPressed: _save,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SecondaryButton(
                                  key: const Key('guestStoryHowTo'),
                                  icon: Icons.help_outline_rounded,
                                  label: 'How to',
                                  onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              GuestStoryHowToScreen(url: url))),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// The picture posted to a story (9:16): my animal, the words and room for
/// the link sticker under them, together in the middle.
class GuestStoryCard extends StatelessWidget {
  const GuestStoryCard({
    super.key,
    required this.animal,
    required this.prompt,
    required this.colors,
    this.photo,
  });

  final String animal;
  final String prompt;
  final List<Color> colors;

  /// A picture of my own behind it (darkened so the words stay readable),
  /// instead of [colors].
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          // square corners: it fills the story edge to edge
          decoration: BoxDecoration(
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
            // the link sticker right under the words
            const SizedBox(height: 20),
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
            const Spacer(),
          ]),
        ),
      );
}

/// A section's column: centred, at most 560 wide, with room at the sides.
class _Column extends StatelessWidget {
  const _Column({required this.child, this.top = 0});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 0),
            child: child,
          ),
        ),
      );
}

/// A titled group on its own surface (Background, Share your link).
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: HuntrColors.orange),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 18),
            child,
          ],
        ),
      );
}

/// Save image / How to: equal, quieter than Share.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: HuntrColors.surfaceHigh,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: HuntrColors.orange),
        // one line, however narrow
        label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, softWrap: false)),
      );
}

class _PhotoSwatch extends StatelessWidget {
  const _PhotoSwatch(
      {required this.photo,
      required this.selected,
      required this.onTap,
      this.size = 52});

  final double size;
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
            width: size,
            height: size,
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
      {required this.colors,
      required this.selected,
      required this.onTap,
      this.size = 52});

  final double size;

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
            width: size,
            height: size,
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
      {required this.number, required this.title, this.child, this.detail});

  final int number;
  final String title;
  final String? detail;
  final Widget? child;

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
                if (child != null) ...[
                  const SizedBox(height: 12),
                  child!,
                ],
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
