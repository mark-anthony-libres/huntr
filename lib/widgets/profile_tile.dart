import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'avatar.dart';

/// One person in the Explore grid: portrait, online dot, name, age and distance.
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
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label:
          '${profile.name}, ${profile.age}, ${profile.distanceLabel}${profile.online ? ', online' : ''}',
      child: Material(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                  tag: 'art-${profile.id}',
                  child: ProfileArt(profile: profile, fontSize: 34)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1],
                    colors: [Colors.transparent, Color(0xD90F1014)],
                  ),
                ),
              ),
              if (profile.online)
                const Positioned(top: 8, left: 8, child: OnlineDot(size: 12)),
              if (favorite)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.star_rounded,
                      size: 18, color: HuntrColors.amber),
                ),
              Positioned(
                left: 9,
                right: 9,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text('  ${profile.age}',
                            style: text.titleSmall
                                ?.copyWith(color: Colors.white70)),
                        if (profile.verified) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.verified,
                              size: 14, color: HuntrColors.amber),
                        ],
                      ],
                    ),
                    Text(
                      profile.distanceLabel,
                      style:
                          text.labelSmall?.copyWith(color: HuntrColors.muted),
                    ),
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
