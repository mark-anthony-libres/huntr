import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import 'gif_bubble.dart';
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

class _GifPickerState extends State<_GifPicker> {
  /// Searches wait for a pause in typing (each one is a GIPHY call).
  static const _typingPause = Duration(milliseconds: 450);

  final _search = TextEditingController();
  Timer? _waitForPause;
  String _query = '';

  @override
  void dispose() {
    _waitForPause?.cancel();
    _search.dispose();
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
    return DefaultTabController(
      length: 3,
      child: SafeArea(
        top: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                  borderSide: BorderSide(color: HuntrColors.orange, width: 1.5),
                ),
              ),
            ),
          ),
          const TabBar(tabs: [
            Tab(key: Key('huntrStickersTab'), text: 'HUNTR'),
            Tab(text: 'GIFs'),
            Tab(text: 'Stickers'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _HuntrStickers(query: _query, sent: widget.sentStickers),
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
      ),
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
/// from the admin dashboard), each with its price in Beans and my balance
/// over them: one I can't afford is greyed out and can't be picked. One
/// already sent to this person says Sent: it counts on their profile until
/// it's undone. In a one-per-person group, once one is sent to them the
/// others wait until it's undone. (The server checks all of it again.)
class _HuntrStickers extends StatefulWidget {
  const _HuntrStickers({required this.query, required this.sent});

  final String query;
  final Set<int> sent;

  @override
  State<_HuntrStickers> createState() => _HuntrStickersState();
}

class _HuntrStickersState extends State<_HuntrStickers>
    with AutomaticKeepAliveClientMixin {
  StickerCatalog? _catalog;
  String? _error;

  // loaded once while the picker is open, not again on each visit to the tab
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final messaging = MessagingScope.read(context);
    if (messaging == null) {
      return setState(() => _catalog = const StickerCatalog(groups: []));
    }
    setState(() => _error = null);
    try {
      final catalog = await messaging.stickerCatalog();
      if (mounted) {
        setState(() => _catalog = catalog ?? const StickerCatalog(groups: []));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is BackendException
          ? error.message
          : "Stickers couldn't load. Check your connection and try again.");
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
    final q = widget.query.toLowerCase();
    final shown = [
      for (final group in catalog.groups)
        if (group.stickers
                .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
                .toList()
            case final stickers when stickers.isNotEmpty)
          (group: group, stickers: stickers),
    ];
    if (shown.isEmpty) {
      return Center(
          child: Text(
              q.isEmpty ? 'No HUNTR stickers yet' : 'No HUNTR stickers found',
              style: const TextStyle(color: HuntrColors.muted)));
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _BeansBalance(beans: catalog.beansBalance)),
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
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8),
              delegate: SliverChildBuilderDelegate(
                childCount: stickers.length,
                (context, i) =>
                    _stickerTile(group, stickers[i], catalog.beansBalance),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stickerTile(
      HuntrStickerGroup group, HuntrSticker sticker, int beans) {
    final already = widget.sent.contains(sticker.id);
    // another of a one-per-person group is out with them
    final groupTaken = !already &&
        group.onePerGroupPerRecipient &&
        group.stickers.any((s) => widget.sent.contains(s.id));
    // exactly enough is enough
    final affordable = sticker.beansCost <= beans;
    final VoidCallback? onTap;
    final String label;
    if (already) {
      label = '${sticker.name}, already sent';
      onTap = () => _explain('You already sent “${sticker.name}”. '
          'Tap it in the chat to undo it.');
    } else if (groupTaken) {
      label = '${sticker.name}, unavailable: one from ${group.name} per person';
      onTap = () => _explain(
          'You can send them one sticker from “${group.name}”. '
          'Undo the one you sent (tap it in the chat) to send a different one.');
    } else if (!affordable) {
      label = '${sticker.name}, costs ${formatBeans(sticker.beansCost)} Beans, '
          'you have ${formatBeans(beans)}';
      onTap = null; // greyed out: can't be picked
    } else {
      label = sticker.name;
      onTap = () => Navigator.of(context).pop(PickedSticker(sticker));
    }
    final cantAfford = !already && !groupTaken && !affordable;
    Widget picture = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 22),
      child: StickerImage(url: sticker.imageUrl, name: sticker.name),
    );
    // greyed (the picture itself is never changed)
    if (cantAfford) {
      picture = ColorFiltered(colorFilter: _greyscale, child: picture);
    }
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('huntrSticker-${sticker.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        mouseCursor: onTap == null
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: Stack(fit: StackFit.expand, children: [
          Opacity(
            opacity: already ? 0.4 : (groupTaken || cantAfford ? 0.35 : 1),
            child: picture,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: already
                ? const _Badge(icon: Icons.check_rounded, text: 'Sent')
                : _Price(
                    key: Key('stickerPrice-${sticker.id}'),
                    beans: sticker.beansCost,
                    short: cantAfford),
          ),
        ]),
      ),
    );
  }
}

/// A group's name over its stickers; for a one-per-person group, the rule
/// (and which one they already have from me).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, this.usedBy});

  final HuntrStickerGroup group;
  final HuntrSticker? usedBy;

  @override
  Widget build(BuildContext context) {
    final used = usedBy;
    return Padding(
      key: Key('stickerGroup-${group.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: Text(group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ),
          if (group.onePerGroupPerRecipient) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          ],
        ]),
        if (used != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
                'You sent them “${used.name}”. Undo it to send a different one.',
                key: Key('stickerGroupUsed-${group.id}'),
                style: const TextStyle(color: HuntrColors.muted, fontSize: 12)),
          ),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(text,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Greys a sticker I can't afford.
const _greyscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// My Beans, over the stickers.
class _BeansBalance extends StatelessWidget {
  const _BeansBalance({required this.beans});

  final int beans;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          key: const Key('beansBalance'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: HuntrColors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: HuntrColors.orange.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(Icons.toll_rounded, color: HuntrColors.orange, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Your Beans',
                  style: TextStyle(color: HuntrColors.muted, fontSize: 13.5)),
            ),
            Text(formatBeans(beans),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

/// A sticker's price under it: Free, or its Beans (muted when I don't have
/// enough).
class _Price extends StatelessWidget {
  const _Price({super.key, required this.beans, required this.short});

  final int beans;

  /// I don't have enough.
  final bool short;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: short
                  ? HuntrColors.border
                  : HuntrColors.orange.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (beans > 0) ...[
            Icon(Icons.toll_rounded,
                size: 13,
                color: short ? HuntrColors.muted : HuntrColors.orange),
            const SizedBox(width: 3),
          ],
          Text(beans > 0 ? formatBeans(beans) : 'Free',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: short ? HuntrColors.muted : Colors.white)),
        ]),
      );
}
