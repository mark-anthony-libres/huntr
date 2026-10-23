import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/nearby_service.dart';
import '../../theme.dart';
import '../../screens/chats_screen.dart' show timeLabel;
import '../anonymous_avatar.dart';

/// A random animal in a circle: who someone is on a Nearby post.
class NearbyAvatar extends StatelessWidget {
  const NearbyAvatar({super.key, required this.animal, this.size = 48});

  final String animal;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: AnonymousArt(animal: animal, radius: size / 2, size: size),
      );
}

/// "320 m away · 12 min ago" (or "You · 120 m away · within 5 km · …" on
/// mine; "here" when it's that close).
String nearbyMeta(
    {required int? distanceM,
    required DateTime at,
    required DateTime now,
    bool mine = false,
    int? radiusM}) {
  final away = distanceM == null
      ? null
      : distanceM < 10
          ? 'here'
          : '${nearbyDistanceLabel(distanceM)} away';
  return [
    if (mine) 'You',
    if (away != null) away,
    if (mine && radiusM != null) 'within ${nearbyRadiusLabel(radiusM)}',
    nearbyAgo(at, now),
  ].join(' · ');
}

/// What can be done with a post or comment from its ⋯: delete mine, or
/// report someone else's.
enum NearbyAction { delete, report }

/// The ⋯ button; [onSelected] gets what was picked.
class NearbyMenu extends StatelessWidget {
  const NearbyMenu({super.key, required this.mine, required this.onSelected});

  final bool mine;
  final ValueChanged<NearbyAction> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<NearbyAction>(
        tooltip: 'More',
        icon: const Icon(Icons.more_horiz, color: HuntrColors.muted),
        onSelected: onSelected,
        itemBuilder: (context) => [
          if (mine)
            const PopupMenuItem(
                value: NearbyAction.delete,
                child: Row(children: [
                  Icon(Icons.delete_outline, color: HuntrColors.coral),
                  SizedBox(width: 10),
                  Text('Delete', style: TextStyle(color: HuntrColors.coral)),
                ]))
          else
            const PopupMenuItem(
                value: NearbyAction.report,
                child: Row(children: [
                  Icon(Icons.flag_outlined),
                  SizedBox(width: 10),
                  Text('Report'),
                ])),
        ],
      );
}

/// A heart and its count (filled when I hearted it).
class NearbyHeart extends StatelessWidget {
  const NearbyHeart(
      {super.key,
      required this.count,
      required this.liked,
      required this.onTap,
      this.size = 22});

  final int count;
  final bool liked;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(liked),
                size: size,
                color: liked ? const Color(0xFFFF4D5E) : Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text('$count', style: const TextStyle(fontSize: 15)),
          ]),
        ),
      );
}

/// A Nearby post: who (a random name and animal), how far and when, what
/// they wrote, its hearts and comments, and how far it is.
class NearbyPostCard extends StatelessWidget {
  const NearbyPostCard({
    super.key,
    required this.post,
    required this.now,
    required this.onLike,
    required this.onAction,
    this.onOpen,
    this.large = false,
  });

  final NearbyPost post;
  final DateTime now;
  final VoidCallback onLike;
  final ValueChanged<NearbyAction> onAction;

  /// Opens its discussion (null: it's the discussion's own header).
  final VoidCallback? onOpen;

  /// The discussion's header: a little bigger.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final distance = post.distanceM;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: Key('nearbyPost-${post.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                NearbyAvatar(animal: post.author.avatar, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // the name, and how long ago (short)
                        Row(children: [
                          Flexible(
                            child: Text(post.author.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                          Text('  ·  ${timeLabel(post.createdAt, now)}',
                              style: const TextStyle(
                                  color: HuntrColors.muted, fontSize: 13)),
                        ]),
                        const SizedBox(height: 2),
                        // how far it is from me (mine too: from where I
                        // wrote it)
                        Row(children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: HuntrColors.muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                                [
                                  if (post.mine) 'You',
                                  distance == null
                                      ? 'Nearby'
                                      : distance < 10
                                          ? 'Right here'
                                          : '${nearbyDistanceLabel(distance)} away',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: HuntrColors.muted, fontSize: 13)),
                          ),
                        ]),
                      ]),
                ),
                NearbyMenu(mine: post.mine, onSelected: onAction),
              ]),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(post.body,
                    style: TextStyle(fontSize: large ? 18 : 16, height: 1.4)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                NearbyHeart(
                    key: Key('nearbyLike-${post.id}'),
                    count: post.likeCount,
                    liked: post.liked,
                    onTap: onLike),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onOpen,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 21),
                      const SizedBox(width: 6),
                      Text('${post.commentCount}',
                          key: Key('nearbyComments-${post.id}'),
                          style: const TextStyle(fontSize: 15)),
                    ]),
                  ),
                ),
                const Spacer(),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Asks why, then reports a post or comment (null: cancelled).
Future<String?> askReportReason(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text("What's wrong with it?",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final (reason, label) in const [
            ('spam', 'Spam'),
            ('harassment', 'Harassment or bullying'),
            ('inappropriate', 'Inappropriate'),
            ('other', 'Something else'),
          ])
            ListTile(
              key: Key('nearbyReport-$reason'),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(reason),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
