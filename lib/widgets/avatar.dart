import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'anonymous_avatar.dart';
import 'network_photo.dart';
import 'stories/story_ring.dart';

/// A generated portrait: a soft two-tone gradient from the person's hue, with their initials.
/// Stands in for profile photos until uploads exist.
class ProfileArt extends StatelessWidget {
  const ProfileArt(
      {super.key,
      required this.profile,
      this.radius = 0,
      this.fontSize = 36,
      this.alignment = Alignment.center});

  final Profile profile;
  final double radius;
  final double fontSize;

  /// Where the initials (or silhouette) sit, e.g. up top on a card whose
  /// bottom holds text.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    // someone anonymous: their animal, never a photo
    if (profile.anonymousAvatar case final animal?) {
      return AnonymousArt(animal: animal, radius: radius, size: fontSize * 2);
    }
    if (profile.backendId != null && profile.photoUrls.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: NetworkPhoto(profile.photoUrls.first),
      );
    }
    final a = HSLColor.fromAHSL(1, profile.hue, 0.55, 0.42).toColor();
    final b =
        HSLColor.fromAHSL(1, (profile.hue + 40) % 360, 0.6, 0.22).toColor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [a, b],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Align(
          alignment: alignment,
          child: profile.initials.isEmpty
              // no name: a person silhouette in a soft circle
              ? Container(
                  width: fontSize * 2,
                  height: fontSize * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Icon(Icons.person_rounded,
                      size: fontSize * 1.35,
                      color: Colors.white.withValues(alpha: 0.85)),
                )
              : Text(
                  profile.initials,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Someone's round picture (with their online dot). When they have a story,
/// a thick ring goes round it, its colors turning while there's one I
/// haven't watched (grey once I've seen them all); never for someone
/// anonymous to me.
class Avatar extends StatelessWidget {
  const Avatar(
      {super.key,
      required this.profile,
      this.size = 48,
      this.showOnline = true,
      this.animateStory = true});

  final Profile profile;
  final double size;
  final bool showOnline;

  /// The story ring's colours turn (off where many are drawn at once over
  /// something costly, like the map).
  final bool animateStory;

  @override
  Widget build(BuildContext context) {
    final Widget art =
        ProfileArt(profile: profile, radius: size / 2, fontSize: size * 0.36);
    final ringed = profile.hasStory && profile.anonymousAvatar == null;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ringed
                ? StoryRing(
                    key: const Key('avatarStoryRing'),
                    seen: profile.storySeen,
                    circle: true,
                    animate: animateStory,
                    width: (size * 0.07).clamp(2.5, 5.0),
                    // a thin dark gap between the ring and the picture
                    child: Container(
                      padding: EdgeInsets.all((size * 0.04).clamp(1.5, 3.0)),
                      decoration: const BoxDecoration(
                          color: HuntrColors.night, shape: BoxShape.circle),
                      child: art,
                    ),
                  )
                : art,
          ),
          if (showOnline && profile.online)
            Positioned(
              right: 0,
              bottom: 0,
              child: OnlineDot(size: size * 0.28),
            ),
        ],
      ),
    );
  }
}

class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, this.size = 10});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HuntrColors.online,
        shape: BoxShape.circle,
        border: Border.all(color: HuntrColors.night, width: size * 0.18),
      ),
    );
  }
}
