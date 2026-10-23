import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'avatar.dart';

/// One person in the Explore grid, a rounded card: portrait, status and
/// badges in the top corners; name, age, distance and what they're looking
/// for along the bottom.
class ProfileTile extends StatelessWidget {
  const ProfileTile(
      {super.key,
      required this.profile,
      required this.onTap,
      this.favorite = false});

  final Profile profile;
  final VoidCallback onTap;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    // 3 across on a phone: smaller badges and text so nothing overlaps
    return LayoutBuilder(
        builder: (context, box) => _tile(context, compact: box.maxWidth < 140));
  }

  Widget _tile(BuildContext context, {required bool compact}) {
    final noName = profile.name.isEmpty;
    final inset = compact ? 7.0 : 12.0;
    // long names (up to 20 characters) a little smaller, and on two lines
    // when they need them, so they show in full
    final long = profile.name.characters.length > 12;
    final nameSize = compact ? (long ? 12.5 : 13.5) : (long ? 17.0 : 20.0);
    return Semantics(
      button: true,
      label:
          '${profile.nameAndAge}, ${profile.distanceLabel}${profile.online ? ', online' : ''}${profile.isNew ? ', new' : ''}',
      child: Material(
        color: HuntrColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                  tag: 'art-${profile.id}',
                  child: ProfileArt(profile: profile, fontSize: 34)),
              // keeps the text readable on any photo
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.35, 1],
                    colors: [Colors.transparent, Color(0xF20F1014)],
                  ),
                ),
              ),

              // ---- top corners: status, then badges ----
              if (profile.online)
                Positioned(
                    top: inset,
                    left: inset,
                    child: compact ? const _OnlineMark() : const _OnlinePill()),
              Positioned(
                top: inset,
                right: inset,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (favorite)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: EdgeInsets.all(compact ? 2 : 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.star_rounded,
                          size: compact ? 16 : 20, color: HuntrColors.orange),
                    ),
                  if (profile.isNew)
                    NewBadge(
                        key: Key('newBadge-${profile.id}'), small: compact),
                ]),
              ),

              // ---- bottom: who and how far ----
              Positioned(
                left: inset,
                right: inset,
                bottom: inset,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // name, age and the verified mark run on together
                    Text.rich(
                      key: const Key('tileName'),
                      TextSpan(children: [
                        if (!noName)
                          TextSpan(
                              text: profile.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        if (!profile.ageHidden)
                          TextSpan(
                              text:
                                  noName ? '${profile.age}' : ' ${profile.age}',
                              style: TextStyle(
                                  fontSize:
                                      noName ? nameSize + 1.5 : nameSize - 1,
                                  fontWeight: noName
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color:
                                      noName ? Colors.white : Colors.white70)),
                        if (profile.verified)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.verified,
                                  size: compact ? 13 : 15,
                                  color: HuntrColors.orange),
                            ),
                          ),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: nameSize, height: 1.15),
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(
                          profile.distanceHidden
                              ? Icons.location_off_outlined
                              : Icons.near_me_rounded,
                          size: compact ? 12 : 15,
                          color: Colors.white70),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          // "4.30 km" fits a phone's narrow tile ("away" doesn't)
                          compact
                              ? profile.distanceLabel.replaceFirst(' away', '')
                              : profile.distanceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: compact ? 11 : 13.5,
                              color: Colors.white70),
                        ),
                      ),
                    ]),
                    if (!compact && profile.lookingFor.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _LookingForTags(profile.lookingFor),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What they're looking for, as small pills (the first one highlighted);
/// one line, whatever doesn't fit is left out.
class _LookingForTags extends StatelessWidget {
  const _LookingForTags(this.lookingFor);

  final Set<LookingFor> lookingFor;

  @override
  Widget build(BuildContext context) {
    final tags = [
      for (final l in LookingFor.values)
        if (lookingFor.contains(l)) l
    ];
    return SizedBox(
      height: 28,
      child: Wrap(
        spacing: 6,
        runSpacing: 8,
        clipBehavior: Clip.hardEdge,
        children: [
          for (final (i, l) in tags.indexed)
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: i == 0
                    ? const Color(0xFF7A3A12).withValues(alpha: 0.9)
                    : Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: i == 0
                        ? const Color(0xFF7A3A12)
                        : Colors.white.withValues(alpha: 0.22)),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(l.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "● Online" on a dark glass pill, readable on any photo.
class _OnlinePill extends StatelessWidget {
  const _OnlinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        OnlineDot(size: 9),
        SizedBox(width: 5),
        Text('Online now',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Just the green dot, on a dark ring (narrow tiles: no room for "Online").
class _OnlineMark extends StatelessWidget {
  const _OnlineMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('onlineMark'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: const OnlineDot(size: 9),
    );
  }
}

/// Joined in the last week.
class NewBadge extends StatelessWidget {
  const NewBadge({super.key, this.small = false});

  /// On a narrow tile.
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: HuntrColors.active,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: HuntrColors.active.withValues(alpha: 0.45), blurRadius: 8),
        ],
      ),
      child: Text('NEW',
          style: TextStyle(
              color: Colors.white,
              fontSize: small ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6)),
    );
  }
}
