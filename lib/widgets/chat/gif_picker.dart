import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import 'gif_bubble.dart';

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
        {Set<String> sentStickers = const {}}) =>
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

  final Set<String> sentStickers;

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

/// HUNTR's stickers (bundled, so they show at once). One already sent to
/// this person says Sent: it counts on their profile until it's undone.
class _HuntrStickers extends StatelessWidget {
  const _HuntrStickers({required this.query, required this.sent});

  final String query;
  final Set<String> sent;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final shown = [
      for (final sticker in HuntrSticker.all)
        if (q.isEmpty || sticker.name.toLowerCase().contains(q)) sticker,
    ];
    if (shown.isEmpty) {
      return const Center(
          child: Text('No HUNTR stickers found',
              style: TextStyle(color: HuntrColors.muted)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final sticker = shown[i];
        final already = sent.contains(sticker.id);
        return Semantics(
          button: true,
          label: already ? '${sticker.name}, already sent' : sticker.name,
          child: InkWell(
            key: Key('huntrSticker-${sticker.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: already
                ? () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                      content: Text('You already sent “${sticker.name}”. '
                          'Tap it in the chat to undo it.')))
                : () => Navigator.of(context).pop(PickedSticker(sticker)),
            child: Stack(fit: StackFit.expand, children: [
              Opacity(
                opacity: already ? 0.4 : 1,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(sticker.asset, fit: BoxFit.contain),
                ),
              ),
              if (already)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HuntrColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: HuntrColors.border),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 3),
                      Text('Sent',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
