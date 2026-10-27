import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart' show BackendException;
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../chat/sticker_image.dart';

/// "What others say about you": the stickers people sent this person in chat, each
/// with how many sent it (never who), most first, in a row that scrolls
/// sideways; See all opens the whole collection. Nothing shows until
/// someone has sent one (nor while loading, nor when they couldn't load). Uses the counts the
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
  static const _gap = 10.0;

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
    if (_failed || stickers == null || stickers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const Key('stickerShelf'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.textsms_outlined, color: HuntrColors.orange, size: 30),
          const SizedBox(width: 14),
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What others say about you',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Stickers from other users',
                  style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
            ]),
          ),
          TextButton(
            key: const Key('stickersSeeAll'),
            style: TextButton.styleFrom(
                foregroundColor: HuntrColors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => showStickerCollection(context, widget.userId,
                initial: stickers),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('See all', style: TextStyle(fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        // compact: five across a phone, at most 92 wide; more scroll sideways
        LayoutBuilder(builder: (context, constraints) {
          final width =
              ((constraints.maxWidth - 4 * _gap) / 5).clamp(64.0, 92.0);
          return SizedBox(
            height: _StickerCard.heightFor(width),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stickers.length,
              separatorBuilder: (_, __) => const SizedBox(width: _gap),
              itemBuilder: (_, i) => SizedBox(
                  width: width, child: _StickerCard(sticker: stickers[i])),
            ),
          );
        }),
      ]),
    );
  }
}

/// One kind of sticker with how many sent it: the sticker big, its name,
/// then the count (people, never who). Fills the width it's given.
class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.sticker});

  final StickerCount sticker;

  /// The height for a card [width] wide: a square for the sticker, then
  /// the name and count.
  static double heightFor(double width) => width - 8 + 44;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('stickerCount-${sticker.id}'),
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Column(children: [
          Expanded(
            child: StickerImage(url: sticker.imageUrl, name: sticker.name),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(sticker.name,
                maxLines: 1,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Semantics(
            label: '${sticker.count} '
                '${sticker.count == 1 ? 'person' : 'people'}',
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.people_alt_rounded,
                  size: 14, color: HuntrColors.muted),
              const SizedBox(width: 4),
              Text('${sticker.count}',
                  style: const TextStyle(
                      color: HuntrColors.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
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
          child: Text('What others say about you',
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
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 100,
                      mainAxisExtent: _StickerCard.heightFor(92),
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
