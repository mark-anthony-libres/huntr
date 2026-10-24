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
      child: DefaultPortrait(alignment: alignment, hue: profile.hue),
    );
  }
}

/// The picture of someone without a photo: a soft two-tone gradient in
/// their own colour (as before photos) or the theme's, a faint glow, and a light
/// head-and-shoulders silhouette fading out at the shoulders - smaller in
/// big spaces (an Explore card), filling small ones (an avatar). In a
/// taller space the figure sits at [alignment].
class DefaultPortrait extends StatelessWidget {
  const DefaultPortrait(
      {super.key, this.alignment = Alignment.center, this.hue});

  final Alignment alignment;

  /// The person's own colour (0-360, the same every time for them); null:
  /// the theme's accent.
  final double? hue;

  @override
  Widget build(BuildContext context) {
    final hue = this.hue;
    // their colour, as a soft two-tone gradient; or the theme's
    final (Color top, Color bottom, Color tint) = hue == null
        ? (
            Color.lerp(HuntrColors.surfaceHigh, HuntrColors.orange, 0.10)!,
            Color.lerp(HuntrColors.night, HuntrColors.orange, 0.22)!,
            HuntrColors.orange,
          )
        : (
            HSLColor.fromAHSL(1, hue, 0.45, 0.36).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.16).toColor(),
            HSLColor.fromAHSL(1, hue, 0.6, 0.62).toColor(),
          );
    return DecoratedBox(
      key: const Key('defaultPortrait'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _SilhouettePainter(
            alignment: alignment,
            figure: Color.lerp(const Color(0xFFE4E6EC), tint, 0.25)!
                .withValues(alpha: 0.6),
            glow: hue == null
                ? HuntrColors.orange.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter(
      {required this.alignment, required this.figure, required this.glow});

  final Alignment alignment;
  final Color figure;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final shortest = size.shortestSide;
    // big spaces: a smaller figure with room round it; avatars: filled
    final side = shortest < 96 ? shortest : shortest * 0.62;
    final origin =
        alignment.inscribe(Size.square(side), Offset.zero & size).topLeft;
    final head = origin + Offset(side * 0.5, side * 0.36);
    // the glow behind the head
    canvas.drawCircle(
      head,
      side * 0.62,
      Paint()
        ..shader = RadialGradient(colors: [glow, glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: head, radius: side * 0.62)),
    );
    canvas.drawCircle(head, side * 0.24, Paint()..color = figure);
    // the shoulders: wide, fading out downwards into the background
    final body = Rect.fromLTRB(origin.dx + side * 0.04, origin.dy + side * 0.68,
        origin.dx + side * 0.96, origin.dy + side * 1.75);
    canvas.drawOval(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [figure, figure.withValues(alpha: 0)],
          stops: const [0.15, 0.62],
        ).createShader(body),
    );
  }

  @override
  bool shouldRepaint(_SilhouettePainter oldDelegate) =>
      oldDelegate.alignment != alignment ||
      oldDelegate.figure != figure ||
      oldDelegate.glow != glow;
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
