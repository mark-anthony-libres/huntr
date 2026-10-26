import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'avatar.dart';

/// One person in the Explore grid, a rounded card: portrait, status and
/// badges in the top corners; along the bottom what [layout] shows (name,
/// age and distance; just the name; or nothing).
class ProfileTile extends StatelessWidget {
  const ProfileTile(
      {super.key,
      required this.profile,
      required this.onTap,
      this.favorite = false,
      this.layout = ExploreLayout.two});

  final Profile profile;
  final VoidCallback onTap;
  final bool favorite;
  final ExploreLayout layout;

  @override
  Widget build(BuildContext context) {
    // 3 across on a phone: smaller badges and text so nothing overlaps
    return LayoutBuilder(
        builder: (context, box) => _tile(context,
            // the small layouts are compact at any width (a dot, not "Online")
            compact: box.maxWidth < 140 ||
                layout == ExploreLayout.three ||
                layout == ExploreLayout.four));
  }

  Widget _tile(BuildContext context, {required bool compact}) {
    final noName = profile.name.isEmpty;
    final inset = compact ? 7.0 : 12.0;
    // what the bottom says: name and distance, just the name, or nothing
    final showName = layout != ExploreLayout.four;
    final showDistance =
        layout == ExploreLayout.two || layout == ExploreLayout.one;
    final showAge = showDistance || noName;
    // long names (up to 20 characters) a little smaller, and on two lines
    // when they need them, so they show in full
    final long = profile.name.characters.length > 12;
    final nameSize = compact ? (long ? 12.5 : 13.5) : (long ? 16.0 : 18.0);
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
                  // the stand-in picture up top, clear of the name below
                  child: ProfileArt(
                      profile: profile,
                      fontSize: 34,
                      alignment: const Alignment(0, -0.45))),
              // keeps the text readable on any photo
              if (showName)
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
              if (showName)
                Positioned(
                  left: inset,
                  right: inset,
                  bottom: inset,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "Name, 24" as on profiles: the age stays with the
                      // name's last word (never alone on a line) and the
                      // verified mark follows
                      Text.rich(
                        key: const Key('tileName'),
                        TextSpan(children: [
                          if (!noName)
                            TextSpan(
                                text: profile.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          if (showAge && !profile.ageHidden)
                            TextSpan(
                                text: noName
                                    ? '${profile.age}'
                                    : ',\u00A0${profile.age}',
                                style: TextStyle(
                                    fontSize: noName ? nameSize + 2 : nameSize,
                                    fontWeight: noName
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: Colors.white)),
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
                      if (showDistance) ...[
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
                                  ? profile.distanceLabel
                                      .replaceFirst(' away', '')
                                  : profile.distanceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: compact ? 11 : 13.5,
                                  color: Colors.white70),
                            ),
                          ),
                        ]),
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

/// One person as a row (the Detailed layout): photo, name and age, bio, and
/// what they're looking for.
class ProfileRowTile extends StatelessWidget {
  const ProfileRowTile(
      {super.key,
      required this.profile,
      required this.onTap,
      this.favorite = false});

  final Profile profile;
  final VoidCallback onTap;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final noName = profile.name.isEmpty;
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 112,
              child: Stack(fit: StackFit.expand, children: [
                Hero(
                    tag: 'art-${profile.id}',
                    child: ProfileArt(profile: profile, fontSize: 28)),
                if (profile.online)
                  const Positioned(top: 7, left: 7, child: _OnlineMark()),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text.rich(
                          key: const Key('tileName'),
                          TextSpan(children: [
                            if (!noName)
                              TextSpan(
                                  text: profile.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            if (!profile.ageHidden)
                              TextSpan(
                                  text: noName
                                      ? '${profile.age}'
                                      : ',\u00A0${profile.age}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            if (profile.verified)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(Icons.verified,
                                      size: 15, color: HuntrColors.orange),
                                ),
                              ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16.5, color: Colors.white),
                        ),
                      ),
                      if (favorite) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star_rounded,
                            size: 18, color: HuntrColors.orange),
                      ],
                      if (profile.isNew) ...[
                        const SizedBox(width: 6),
                        NewBadge(
                            key: Key('newBadge-${profile.id}'), small: true),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        profile.bio.trim().isEmpty
                            ? 'No bio yet.'
                            : profile.bio.trim(),
                        key: const Key('tileBio'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            color: profile.bio.trim().isEmpty
                                ? HuntrColors.muted
                                : Colors.white.withValues(alpha: 0.85),
                            fontStyle: profile.bio.trim().isEmpty
                                ? FontStyle.italic
                                : null),
                      ),
                    ),
                    if (profile.lookingFor.isNotEmpty)
                      SizedBox(
                        height: 24,
                        child: ListView(
                          key: const Key('tileLookingFor'),
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (final want in profile.lookingFor)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: HuntrColors.orange
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(want.icon,
                                          size: 13, color: HuntrColors.orange),
                                      const SizedBox(width: 4),
                                      Text(want.label,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: HuntrColors.orange)),
                                    ]),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
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
