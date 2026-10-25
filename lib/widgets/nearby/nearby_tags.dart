import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// A post's tags as small "#Sex" pills under its text: the first [limit]
/// (all when null), then a quiet "See more" that shows the rest. Nothing
/// when it has none.
class NearbyTagPills extends StatefulWidget {
  const NearbyTagPills({super.key, required this.tags, this.limit});

  final List<NearbyTag> tags;
  final int? limit;

  @override
  State<NearbyTagPills> createState() => _NearbyTagPillsState();
}

class _NearbyTagPillsState extends State<NearbyTagPills> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    if (tags.isEmpty) return const SizedBox.shrink();
    final limit = widget.limit;
    final cut = !_all && limit != null && tags.length > limit;
    final shown = cut ? tags.take(limit) : tags;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in shown) _HashPill(tag: tag),
          if (cut)
            InkWell(
              key: const Key('nearbyTagsMore'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _all = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text('See more',
                    style: TextStyle(
                        color: HuntrColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

class _HashPill extends StatelessWidget {
  const _HashPill({required this.tag});

  final NearbyTag tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('nearbyTag-${tag.slug}'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: HuntrColors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '#',
            style: TextStyle(
                color: HuntrColors.orange, fontWeight: FontWeight.w800)),
        TextSpan(text: tag.name),
      ])),
    );
  }
}

/// Picks a post's tags: Looking for and Meet preference, each folding
/// away, as pills that turn orange when picked (tap again to unpick). Done
/// gives the picked ids; closing gives null (nothing changes).
Future<Set<int>?> pickNearbyTags(BuildContext context,
        {required Future<List<NearbyTagCategory>> Function() load,
        required Set<int> picked}) =>
    showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HuntrColors.surface,
      builder: (context) => _TagSheet(load: load, picked: picked),
    );

class _TagSheet extends StatefulWidget {
  const _TagSheet({required this.load, required this.picked});

  final Future<List<NearbyTagCategory>> Function() load;
  final Set<int> picked;

  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  late final Set<int> _picked = {...widget.picked};
  late Future<List<NearbyTagCategory>> _categories = widget.load();
  final _folded = <String>{};

  static const _icons = {
    'looking_for': Icons.favorite_rounded,
    'meet_preference': Icons.location_on_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 4),
            child: Row(children: [
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(
                child: Text('Select tags',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                key: const Key('nearbyTagsDone'),
                onPressed: () => Navigator.of(context).pop(_picked),
                child: Text('Done',
                    style: TextStyle(
                        color: HuntrColors.orange,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Flexible(
            child: FutureBuilder<List<NearbyTagCategory>>(
              future: _categories,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text("Tags couldn't load.",
                          style: TextStyle(color: HuntrColors.muted)),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('nearbyTagsRetry'),
                        onPressed: () =>
                            setState(() => _categories = widget.load()),
                        child: const Text('Try again'),
                      ),
                    ]),
                  );
                }
                final categories = snapshot.data;
                if (categories == null) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    for (final (i, category) in categories.indexed) ...[
                      if (i > 0)
                        const Divider(color: HuntrColors.border, height: 24),
                      _group(category),
                    ],
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _group(NearbyTagCategory category) {
    final open = !_folded.contains(category.key);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        key: Key('nearbyTagGroup-${category.key}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() =>
            open ? _folded.add(category.key) : _folded.remove(category.key)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(children: [
            Icon(_icons[category.key] ?? Icons.tag_rounded,
                color: category.key == 'looking_for'
                    ? HuntrColors.coral
                    : HuntrColors.orange,
                size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(category.label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: HuntrColors.muted),
          ]),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final tag in category.tags) _pill(tag),
          ]),
        ),
    ]);
  }

  Widget _pill(NearbyTag tag) {
    final on = _picked.contains(tag.id);
    return Material(
      color: on ? HuntrColors.orange : Colors.transparent,
      shape: StadiumBorder(
          side: BorderSide(
              color: on ? HuntrColors.orange : HuntrColors.border, width: 1.2)),
      child: InkWell(
        key: Key('nearbyTagPick-${tag.slug}'),
        customBorder: const StadiumBorder(),
        onTap: () =>
            setState(() => on ? _picked.remove(tag.id) : _picked.add(tag.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(tag.name,
              style: TextStyle(
                  color: on ? Colors.black : Colors.white,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }
}
