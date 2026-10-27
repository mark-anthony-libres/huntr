import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import 'gif_bubble.dart';
import 'sticker_bubble.dart' show confirmStickerUndo;
import 'sticker_image.dart';

/// What the picker returns: a GIF or sticker from GIPHY, or one of HUNTR's
/// stickers.
sealed class ChatPick {
  const ChatPick();
}

class PickedGif extends ChatPick {
  const PickedGif(this.gif);
  final ChatGif gif;
}

class PickedSticker extends ChatPick {
  const PickedSticker(this.sticker);
  final HuntrSticker sticker;
}

/// One of HUNTR's stickers I already sent them, to take back (confirmed).
class UndoPickedSticker extends ChatPick {
  const UndoPickedSticker(this.sticker);
  final HuntrSticker sticker;
}

/// The GIF picker: HUNTR's stickers first ([sentStickers]: the ones already
/// sent to this person, which can't be sent again until undone), then GIFs
/// and stickers from GIPHY, trending until something is searched. Returns
/// the one picked (null: closed).
Future<ChatPick?> showGifPicker(BuildContext context,
        {Set<int> sentStickers = const {}}) =>
    showModalBottomSheet<ChatPick>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: _GifPicker(sentStickers: sentStickers),
      ),
    );

class _GifPicker extends StatefulWidget {
  const _GifPicker({required this.sentStickers});

  final Set<int> sentStickers;

  @override
  State<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<_GifPicker>
    with SingleTickerProviderStateMixin {
  /// Searches wait for a pause in typing (each one is a GIPHY call).
  static const _typingPause = Duration(milliseconds: 450);

  final _search = TextEditingController();
  Timer? _waitForPause;
  String _query = '';

  // the Beans show beside the search on the HUNTR tab, and only there
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() => setState(() {}));

  /// My Beans, once HUNTR's stickers are in.
  int? _beans;

  @override
  void dispose() {
    _waitForPause?.cancel();
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _typed(String text) {
    setState(() {}); // the clear button follows the text
    _waitForPause?.cancel();
    _waitForPause = Timer(_typingPause, () {
      final query = text.trim();
      if (mounted && query != _query) setState(() => _query = query);
    });
  }

  /// Back to trending, at once.
  void _clear() {
    _waitForPause?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final beans = _tabs.index == 0 ? _beans : null;
    return SafeArea(
      top: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Expanded(
              // the sheet is the app's input colour, so the box gets its own
              child: TextField(
                key: const Key('gifSearch'),
                controller: _search,
                onChanged: _typed,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search stickers and GIFs',
                  hintStyle: const TextStyle(color: HuntrColors.muted),
                  fillColor: HuntrColors.surfaceHigh,
                  prefixIcon: const Icon(Icons.search_rounded),
                  prefixIconColor: WidgetStateColor.resolveWith((states) =>
                      states.contains(WidgetState.focused)
                          ? HuntrColors.orange
                          : HuntrColors.muted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('gifSearchClear'),
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clear,
                        ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: HuntrColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide:
                        BorderSide(color: HuntrColors.orange, width: 1.5),
                  ),
                ),
              ),
            ),
            if (beans != null) ...[
              const SizedBox(width: 14),
              Semantics(
                label: 'You have ${formatBeans(beans)} Beans',
                excludeSemantics: true,
                child: Row(key: const Key('beansBalance'), children: [
                  const BeanIcon(size: 22),
                  const SizedBox(width: 6),
                  Text(formatBeans(beans),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 4),
            ],
          ]),
        ),
        TabBar(controller: _tabs, tabs: const [
          Tab(key: Key('huntrStickersTab'), text: 'HUNTR'),
          Tab(text: 'GIFs'),
          Tab(text: 'Stickers'),
        ]),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _HuntrStickers(
                query: _query,
                sent: widget.sentStickers,
                onBeans: (beans) => setState(() => _beans = beans)),
            _GifResults(key: ValueKey('gif:$_query'), query: _query),
            _GifResults(
                key: ValueKey('sticker:$_query'),
                query: _query,
                stickers: true),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Powered by GIPHY',
              style: TextStyle(color: HuntrColors.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}

/// One tab's results, loading more as the grid nears its end.
class _GifResults extends StatefulWidget {
  const _GifResults({super.key, required this.query, this.stickers = false});

  final String query;
  final bool stickers;

  @override
  State<_GifResults> createState() => _GifResultsState();
}

class _GifResultsState extends State<_GifResults> {
  final List<ChatGif> _gifs = [];
  int? _nextOffset = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    final offset = _nextOffset;
    final messaging = MessagingScope.read(context);
    if (_loading || offset == null || messaging == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await messaging.gifs(
          stickers: widget.stickers, query: widget.query, offset: offset);
      if (!mounted) return;
      setState(() {
        _gifs.addAll(page?.gifs ?? const []);
        _nextOffset = page?.nextOffset;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is BackendException
          ? error.message
          : "GIFs couldn't load. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.stickers ? 'stickers' : 'GIFs';
    if (_gifs.isEmpty) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _loadMore, child: const Text('Try again')),
            ]),
          ),
        );
      }
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Text('No $what found',
                style: const TextStyle(color: HuntrColors.muted)),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140, mainAxisSpacing: 6, crossAxisSpacing: 6),
        itemCount: _gifs.length,
        itemBuilder: (context, i) {
          final gif = _gifs[i];
          return Semantics(
            button: true,
            label: gif.title.isEmpty ? what : gif.title,
            child: InkWell(
              key: Key('gif-${gif.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pop(PickedGif(gif)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GifImage(
                    url: gif.previewUrl,
                    fit: gif.isSticker ? BoxFit.contain : BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// HUNTR's stickers, in the server's groups (sections, in their order; run
/// from the admin dashboard): each group's name and line over its stickers,
/// a page at a time from the server (the next as the list nears its end;
/// a search asks the server too). Each sticker is a card with its price
/// in Beans (my balance is beside the search, [onBeans]); one I can't afford
/// is greyed out with a lock and can't be picked. One already sent to this
/// person says Sent: it counts on their profile until it's undone. In a
/// one-per-person group, once one is sent to them the others wait until
/// it's undone. (The server checks all of it again.)
class _HuntrStickers extends StatefulWidget {
  const _HuntrStickers(
      {required this.query, required this.sent, required this.onBeans});

  final String query;
  final Set<int> sent;
  final ValueChanged<int> onBeans;

  @override
  State<_HuntrStickers> createState() => _HuntrStickersState();
}

class _HuntrStickersState extends State<_HuntrStickers>
    with AutomaticKeepAliveClientMixin {
  StickerCatalog? _catalog;
  String? _error;
  bool _loadingMore = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A page that doesn't fill the sheet: the next one at once (there's
  /// nothing to scroll to ask for it).
  void _fillSheet() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _scroll.hasClients &&
            _scroll.position.extentAfter < 600) {
          _loadMore();
        }
      });

  /// What [_catalog] was loaded for (a new search starts again).
  String _loadedFor = '';

  // loaded once while the picker is open, not again on each visit to the tab
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_HuntrStickers old) {
    super.didUpdateWidget(old);
    if (widget.query != _loadedFor) _load();
  }

  /// The first page (for the search as it is now).
  Future<void> _load() async {
    final messaging = MessagingScope.read(context);
    if (messaging == null) {
      return setState(() => _catalog = const StickerCatalog(groups: []));
    }
    final query = widget.query;
    setState(() {
      _error = null;
      _loadedFor = query;
      _catalog = null;
    });
    try {
      final catalog = await messaging.stickerCatalog(query: query);
      if (!mounted || query != _loadedFor) return; // a newer search
      setState(() => _catalog = catalog ?? const StickerCatalog(groups: []));
      widget.onBeans(_catalog!.beansBalance);
      _fillSheet();
    } catch (error) {
      if (!mounted || query != _loadedFor) return;
      setState(() => _error = error is BackendException
          ? error.message
          : "Stickers couldn't load. Check your connection and try again.");
    }
  }

  /// The next page, as the list nears its end (one at a time).
  Future<void> _loadMore() async {
    final catalog = _catalog, offset = _catalog?.nextOffset;
    final messaging = MessagingScope.read(context);
    if (catalog == null ||
        offset == null ||
        _loadingMore ||
        messaging == null) {
      return;
    }
    final query = _loadedFor;
    setState(() => _loadingMore = true);
    try {
      final next = await messaging.stickerCatalog(offset: offset, query: query);
      if (!mounted || query != _loadedFor || next == null) return;
      setState(() => _catalog = catalog.followedBy(next));
      _fillSheet();
      widget.onBeans(next.beansBalance);
    } catch (_) {
      // scrolling again tries again
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _explain(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final catalog = _catalog;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    if (catalog == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final searching = _loadedFor.isNotEmpty;
    // the server found them (a search included)
    final shown = [
      for (final group in catalog.groups)
        if (group.stickers.isNotEmpty) (group: group, stickers: group.stickers),
    ];
    if (shown.isEmpty) {
      return Center(
          child: Text(
              searching ? 'No HUNTR stickers found' : 'No HUNTR stickers yet',
              style: const TextStyle(color: HuntrColors.muted)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      // as many cards across as fit (at least 3)
      final across = ((constraints.maxWidth - 24) / (_cardWidth + _gap))
          .floor()
          .clamp(3, 8);
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _loadMore();
          return false;
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            for (final (:group, :stickers) in shown) ...[
              SliverToBoxAdapter(
                child: _GroupHeader(
                  group: group,
                  // what I've sent them from this group, if it's one per person
                  usedBy: group.onePerGroupPerRecipient
                      ? group.stickers
                          .where((s) => widget.sent.contains(s.id))
                          .firstOrNull
                      : null,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: across,
                      mainAxisSpacing: _gap,
                      crossAxisSpacing: _gap,
                      childAspectRatio: 0.8),
                  delegate: SliverChildBuilderDelegate(
                    childCount: stickers.length,
                    (context, i) =>
                        _stickerCard(group, stickers[i], catalog.beansBalance),
                  ),
                ),
              ),
            ],
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5))),
                ),
              ),
          ],
        ),
      );
    });
  }

  static const _cardWidth = 104.0;
  static const _gap = 10.0;

  Widget _stickerCard(
      HuntrStickerGroup group, HuntrSticker sticker, int beans) {
    final already = widget.sent.contains(sticker.id);
    // another of a one-per-person group is out with them
    final groupTaken = !already &&
        group.onePerGroupPerRecipient &&
        group.stickers.any((s) => widget.sent.contains(s.id));
    // exactly enough is enough
    final cantAfford = !already && !groupTaken && sticker.beansCost > beans;
    final VoidCallback? onTap;
    final String label;
    if (already) {
      label = '${sticker.name}, already sent: tap to undo';
      onTap = () async {
        if (await confirmStickerUndo(context,
                name: sticker.name, imageUrl: sticker.imageUrl) &&
            mounted) {
          Navigator.of(context).pop(UndoPickedSticker(sticker));
        }
      };
    } else if (groupTaken) {
      label = '${sticker.name}, unavailable: one from ${group.name} per person';
      onTap = () => _explain(
          'You can send them one sticker from “${group.name}”. '
          'Undo the one you sent (tap it in the chat) to send a different one.');
    } else if (cantAfford) {
      label = '${sticker.name}, costs ${formatBeans(sticker.beansCost)} Beans, '
          'you have ${formatBeans(beans)}';
      onTap = null; // greyed out and locked: can't be picked
    } else {
      label = sticker.name;
      onTap = () => Navigator.of(context).pop(PickedSticker(sticker));
    }
    final dim = cantAfford || groupTaken;
    Widget picture = StickerImage(url: sticker.imageUrl, name: sticker.name);
    // greyed (the picture itself is never changed)
    if (cantAfford) {
      picture = ColorFiltered(colorFilter: _greyscale, child: picture);
    }
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('huntrSticker-${sticker.id}'),
          onTap: onTap,
          mouseCursor: onTap == null
              ? SystemMouseCursors.forbidden
              : SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  Opacity(opacity: dim ? 0.35 : 1, child: picture),
                  if (cantAfford)
                    const Center(
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: Color(0xCC0C0C0F),
                        child: Icon(Icons.lock_rounded,
                            size: 15, color: Colors.white),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Text(sticker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: dim ? HuntrColors.muted : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              already
                  ? const _Pill(
                      icon: Icon(Icons.check_rounded, size: 14), text: 'Sent')
                  : _Pill(
                      key: Key('stickerPrice-${sticker.id}'),
                      icon: sticker.beansCost > 0
                          ? BeanIcon(size: 14, muted: dim)
                          : null,
                      text: sticker.beansCost > 0
                          ? formatBeans(sticker.beansCost)
                          : 'Free',
                      muted: dim),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A group's name and line over its stickers; for a one-per-person group,
/// the rule (and which one they already have from me).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, this.usedBy});

  final HuntrStickerGroup group;
  final HuntrSticker? usedBy;

  @override
  Widget build(BuildContext context) {
    final used = usedBy;
    final description = group.description;
    return Padding(
      key: Key('stickerGroup-${group.id}'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(group.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  if (group.onePerGroupPerRecipient)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: HuntrColors.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('One per person',
                          style: TextStyle(
                              color: HuntrColors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                ]),
            if (description != null && description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(description,
                    style: const TextStyle(
                        color: HuntrColors.muted, fontSize: 13.5)),
              ),
            if (used != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                    'You sent them “${used.name}”. Undo it to send a different one.',
                    key: Key('stickerGroupUsed-${group.id}'),
                    style: const TextStyle(
                        color: HuntrColors.muted, fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Greys a sticker I can't afford.
const _greyscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// A sticker's price (or Sent) under it.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, this.icon, this.muted = false});

  final String text;
  final Widget? icon;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            IconTheme.merge(
                data: IconThemeData(
                    color: muted ? HuntrColors.muted : Colors.white),
                child: icon!),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted ? HuntrColors.muted : Colors.white)),
          ),
        ]),
      );
}

/// A Bean: HUNTR's sticker money (orange; grey when [muted]).
class BeanIcon extends StatelessWidget {
  const BeanIcon({super.key, this.size = 16, this.muted = false});

  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
            painter:
                _BeanPainter(muted ? HuntrColors.muted : HuntrColors.orange)),
      );
}

class _BeanPainter extends CustomPainter {
  const _BeanPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    // a bean, leaning a little
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.5);
    final body =
        Rect.fromCenter(center: Offset.zero, width: w * 0.72, height: h * 0.96);
    canvas.drawOval(body, Paint()..color = color);
    // its crease
    final crease = Path()
      ..moveTo(0, -body.height * 0.38)
      ..cubicTo(body.width * 0.28, -body.height * 0.12, -body.width * 0.28,
          body.height * 0.12, 0, body.height * 0.38);
    canvas.drawPath(
        crease,
        Paint()
          ..color = const Color(0xFF0C0C0F).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.09
          ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BeanPainter old) => old.color != color;
}
