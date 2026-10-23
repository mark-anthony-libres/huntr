import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import 'gif_bubble.dart';

/// The GIF picker (GIFs and stickers, from GIPHY): trending until something
/// is searched. Returns the one picked (null: closed).
Future<ChatGif?> showGifPicker(BuildContext context) =>
    showModalBottomSheet<ChatGif>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: const _GifPicker(),
      ),
    );

class _GifPicker extends StatefulWidget {
  const _GifPicker();

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
      length: 2,
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
                hintText: 'Search GIFs and stickers',
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
                      const BorderSide(color: HuntrColors.orange, width: 1.5),
                ),
              ),
            ),
          ),
          const TabBar(tabs: [Tab(text: 'GIFs'), Tab(text: 'Stickers')]),
          Expanded(
            child: TabBarView(children: [
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
              onTap: () => Navigator.of(context).pop(gif),
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
