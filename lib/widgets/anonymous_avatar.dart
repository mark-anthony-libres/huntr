import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'avatar.dart' show OnlineDot;

import '../theme.dart';

/// The cartoon animals anonymous senders are shown as (the backend picks
/// one per anonymous conversation, by name: wolf, pig, ...).
const anonymousAnimals = {
  'wolf': '🐺',
  'pig': '🐷',
  'horse': '🐴',
  'cat': '🐱',
  'tiger': '🐯',
  'fox': '🦊',
  'panda': '🐼',
  'rabbit': '🐰',
  'bear': '🐻',
  'penguin': '🐧',
};

/// An anonymous sender's picture: their animal on a dark, warm background
/// with an orange ring. Never their photo.
class AnonymousArt extends StatelessWidget {
  const AnonymousArt(
      {super.key, required this.animal, this.radius = 0, this.size = 72});

  final String animal;

  /// Corner radius (half the size for a circle).
  final double radius;

  /// How big the animal is drawn.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const RadialGradient(
            colors: [Color(0xFF3A2414), Color(0xFF15100D)],
            radius: 0.9,
          ),
          borderRadius: BorderRadius.circular(radius),
          // a ring on round pictures; tiles fill edge to edge
          border: radius > 0
              ? Border.all(
                  color: HuntrColors.orange.withValues(alpha: 0.85),
                  width: (size / 30).clamp(1.5, 3))
              : null,
        ),
        child: Center(
          child: Text(
            anonymousAnimals[animal] ?? anonymousAnimals['fox']!,
            key: Key('anonymousAnimal-$animal'),
            style: TextStyle(fontSize: size * 0.62, height: 1),
          ),
        ),
      ),
    );
  }
}

/// Over a picture, in chats where I'm the anonymous one: the picture
/// blurred and darkened with a mask in the middle, so it's clear they don't
/// see who I am. [online] keeps the green dot sharp on top.
class MaskOverlay extends StatelessWidget {
  const MaskOverlay(
      {super.key,
      required this.size,
      required this.child,
      this.online = false});

  final double size;

  /// The picture, without its own online dot.
  final Widget child;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: ClipOval(
            child: Stack(fit: StackFit.expand, children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                    sigmaX: size / 9,
                    sigmaY: size / 9,
                    tileMode: TileMode.decal),
                child: child,
              ),
              ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
              Center(
                child: Icon(Icons.theater_comedy_rounded,
                    key: const Key('maskOverlay'),
                    size: size * 0.5,
                    color: HuntrColors.orange,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 8),
                    ]),
              ),
            ]),
          ),
        ),
        if (online)
          Positioned(right: 0, bottom: 0, child: OnlineDot(size: size * 0.28)),
      ]),
    );
  }
}
