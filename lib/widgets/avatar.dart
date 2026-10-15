import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// A generated portrait: a soft two-tone gradient from the person's hue, with their initials.
/// Stands in for profile photos until uploads exist.
class ProfileArt extends StatelessWidget {
  const ProfileArt({super.key, required this.profile, this.radius = 0, this.fontSize = 36});

  final Profile profile;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final a = HSLColor.fromAHSL(1, profile.hue, 0.55, 0.42).toColor();
    final b = HSLColor.fromAHSL(1, (profile.hue + 40) % 360, 0.6, 0.22).toColor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: Text(
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

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.profile, this.size = 48, this.showOnline = true});

  final Profile profile;
  final double size;
  final bool showOnline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: ProfileArt(profile: profile, radius: size / 2, fontSize: size * 0.36)),
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
