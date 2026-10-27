import 'package:flutter/material.dart';

import '../../models/stickers.dart';
import '../../services/huntr_backend.dart' show BackendException;
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../chat/sticker_image.dart';

/// The stickers people sent this person in chat, each with how many sent
/// it (never who), most first, in a row that scrolls sideways; See all opens
/// the whole collection. Titled "What others say about you" on my own
/// profile and "Testimonials" on anyone else's (by whether its [userId] is
/// mine). The profile only shows it when there are some; the backend counts
/// only active stickers, and none between two people where one blocks the
/// other.
class StickerShelf extends StatelessWidget {
  const StickerShelf({super.key, required this.userId, required this.stickers});

  final int userId;
  final List<StickerCount> stickers;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final title = stickerSectionTitle(context, userId);
    return Padding(
      key: const Key('stickerShelf'),
      // as the profile's other sections
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.textsms_outlined,
                color: HuntrColors.orange, size: 26),
          ),
          const SizedBox(width: 12),
          // the title wraps rather than running into See all
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  key: const Key('stickerShelfTitle'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              const Text('Stickers from other users',
                  style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('stickersSeeAll'),
            style: TextButton.styleFrom(
                foregroundColor: HuntrColors.orange,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => showStickerCollection(context, userId,
                title: title, initial: stickers),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('See all', style: TextStyle(fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        // compact cards of one size: five across a phone, at most 92 wide
        // (they don't stretch on wide screens); more scroll sideways
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

/// The section's title: mine or someone else's, by the signed-in account.
String stickerSectionTitle(BuildContext context, int userId) =>
    AppScope.of(context).myUserId == userId
        ? 'What others say about you'
        : 'Testimonials';

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
          // a long name is cut short (it's read in full in See all)
          Text(sticker.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
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
        {required String title, List<StickerCount> initial = const []}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child:
            _StickerCollection(userId: userId, title: title, initial: initial),
      ),
    );

class _StickerCollection extends StatefulWidget {
  const _StickerCollection(
      {required this.userId, required this.title, required this.initial});

  final int userId;
  final String title;
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(widget.title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                  itemBuilder: (_, i) => Tooltip(
                      message: _stickers[i].name,
                      child: _StickerCard(sticker: _stickers[i])),
                ),
        ),
      ]),
    );
  }
}
