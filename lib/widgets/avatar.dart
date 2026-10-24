import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'anonymous_avatar.dart';
import 'network_photo.dart';
import 'stories/story_ring.dart';

/// Someone's picture: their first photo, their animal when they're
/// anonymous to me, or (no photo) [DefaultPortrait].
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

  /// Where the silhouette sits (no photo), e.g. up top on a card whose
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
    // no photo: the default picture, a dark head-and-shoulders silhouette
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DefaultPortrait(alignment: alignment),
    );
  }
}

/// The picture of someone without a photo: a black head and shoulders on
/// grey, sized to the narrower side; in a taller space the head sits at
/// [alignment] and the shoulders run down to the bottom edge.
class DefaultPortrait extends StatelessWidget {
  const DefaultPortrait({super.key, this.alignment = Alignment.center});

  final Alignment alignment;

  static const background = Color(0xFF4A4A4A);

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const Key('defaultPortrait'),
        color: background,
        child: SizedBox.expand(
          child: CustomPaint(painter: _SilhouettePainter(alignment)),
        ),
      );
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter(this.alignment);

  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final side = size.shortestSide;
    // the square the figure is drawn in, placed by [alignment]
    final origin =
        alignment.inscribe(Size.square(side), Offset.zero & size).topLeft;
    final paint = Paint()..color = Colors.black;
    // the head
    canvas.drawCircle(
        origin + Offset(side * 0.5, side * 0.35), side * 0.28, paint);
    // the shoulders, running off the bottom (of the space, when taller)
    final top = origin.dy + side * 0.665;
    final bottom = (size.height - top) < side * 0.6
        ? origin.dy + side * 1.45
        : size.height + side * 0.45;
    canvas.drawOval(
        Rect.fromLTRB(
            origin.dx + side * 0.06, top, origin.dx + side * 0.94, bottom),
        paint);
  }

  @override
  bool shouldRepaint(_SilhouettePainter oldDelegate) =>
      oldDelegate.alignment != alignment;
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
