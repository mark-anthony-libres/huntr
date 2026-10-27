import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart' show BackendException;
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// "The word on you 👀": the stickers people sent this person in chat, each
/// with how many sent it (never who), most first, in a row that scrolls
/// sideways; See all opens the whole collection. Uses the counts the
/// profile came with ([initial]); without them (my own preview) it loads
/// them. The backend counts only active stickers, and none between two
/// people where one blocks the other.
class StickerShelf extends StatefulWidget {
  const StickerShelf({super.key, required this.userId, this.initial});

  final int userId;
  final List<StickerCount>? initial;

  @override
  State<StickerShelf> createState() => _StickerShelfState();
}

class _StickerShelfState extends State<StickerShelf> {
  List<StickerCount>? _stickers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _stickers = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stickers == null && !_failed) _load();
  }

  @override
  void didUpdateWidget(StickerShelf old) {
    super.didUpdateWidget(old);
    // the profile was loaded again (e.g. after a sticker was sent or undone)
    if (widget.initial != null && widget.initial != old.initial) {
      _stickers = widget.initial;
    }
  }

  Future<void> _load() async {
    final explore = ServicesScope.exploreOf(context);
    final token = AppScope.read(context).sessionToken;
    if (explore == null || token == null) {
      setState(() => _stickers = const []);
      return;
    }
    try {
      final stickers = await explore.fetchStickers(token, widget.userId);
      if (mounted) setState(() => _stickers = stickers);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stickers = _stickers;
    return Padding(
      key: const Key('stickerShelf'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('The word on you 👀',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Stickers others have sent',
                      style:
                          TextStyle(color: HuntrColors.muted, fontSize: 13)),
                ]),
          ),
          if (stickers != null && stickers.isNotEmpty)
            TextButton(
              key: const Key('stickersSeeAll'),
              style: TextButton.styleFrom(
                  foregroundColor: HuntrColors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () => showStickerCollection(context, widget.userId,
                  initial: stickers),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('See all',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Icon(Icons.chevron_right_rounded, size: 20),
              ]),
            ),
        ]),
        const SizedBox(height: 12),
        if (_failed)
          TextButton.icon(
            onPressed: () {
              setState(() => _failed = false);
              _load();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text("Stickers couldn't load. Try again"),
          )
        else if (stickers == null)
          const SizedBox(
              height: _StickerCard.height,
              child: Center(
                  child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5))))
        else if (stickers.isEmpty)
          const Text('No stickers yet — be the first to send one.',
              key: Key('stickersEmpty'),
              style: TextStyle(color: HuntrColors.muted, fontSize: 14))
        else
          SizedBox(
            height: _StickerCard.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stickers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _StickerCard(sticker: stickers[i]),
            ),
          ),
      ]),
    );
  }
}

/// One kind of sticker with its count: compact, the sticker leading.
class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.sticker});

  final StickerCount sticker;

  static const width = 100.0;
  static const height = 128.0;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('stickerCount-${sticker.id}'),
        width: width,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Column(children: [
          Expanded(
            child: Image.asset(sticker.asset,
                fit: BoxFit.contain,
                semanticLabel: '${sticker.name} sticker',
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.auto_awesome, color: HuntrColors.muted)),
          ),
          const SizedBox(height: 6),
          Text(sticker.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text('${sticker.count}',
              style: TextStyle(
                  color: HuntrColors.orange,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}

/// All the stickers on someone's profile, fresh from the server (what came
/// with the profile shows meanwhile).
Future<void> showStickerCollection(BuildContext context, int userId,
        {List<StickerCount> initial = const []}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child: _StickerCollection(userId: userId, initial: initial),
      ),
    );

class _StickerCollection extends StatefulWidget {
  const _StickerCollection({required this.userId, required this.initial});

  final int userId;
  final List<StickerCount> initial;

  @override
  State<_StickerCollection> createState() => _StickerCollectionState();
}

class _StickerCollectionState extends State<_StickerCollection> {
  late List<StickerCount> _stickers = widget.initial;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final explore = ServicesScope.exploreOf(context);
    final token = AppScope.read(context).sessionToken;
    if (explore == null || token == null) return;
    try {
      final fresh = await explore.fetchStickers(token, widget.userId);
      if (mounted) setState(() => _stickers = fresh);
    } catch (error) {
      if (mounted && _stickers.isEmpty) {
        setState(() => _error = error is BackendException
            ? error.message
            : "Stickers couldn't load. Check your connection.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('The word on you 👀',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
              'Stickers people sent in chat, and how many sent each. '
              "Just for fun: they're reactions, not facts.",
              style: TextStyle(color: HuntrColors.muted, height: 1.4)),
        ),
        Expanded(
          child: _stickers.isEmpty
              ? Center(
                  child: Text(
                      _error ?? 'No stickers yet — be the first to send one.',
                      style: const TextStyle(color: HuntrColors.muted)))
              : GridView.builder(
                  key: const Key('stickerCollection'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 120,
                      mainAxisExtent: _StickerCard.height,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10),
                  itemCount: _stickers.length,
                  itemBuilder: (_, i) => _StickerCard(sticker: _stickers[i]),
                ),
        ),
      ]),
    );
  }
}
