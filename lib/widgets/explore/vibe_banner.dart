import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../avatar.dart';

/// "Find your vibe": people nearby looking for what I'm looking for. Tapping
/// filters Explore to them. Not shown when there's no one. Swiped away left or
/// right on a phone or tablet (the app, or the web version in its browser);
/// on desktop it has a Hide button instead.
class VibeBanner extends StatelessWidget {
  const VibeBanner(
      {super.key,
      required this.people,
      required this.onTap,
      required this.onHide});

  /// Who wants what I want (the first three are shown).
  final List<Profile> people;
  final VoidCallback onTap;
  final VoidCallback onHide;

  static const _edge = Color(0xFF4A3528);

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final faces = people.take(3).toList();
    // the web version reports the browser's OS, so a phone's browser counts
    final touch = const {TargetPlatform.android, TargetPlatform.iOS}
        .contains(defaultTargetPlatform);
    final banner = Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Material(
        key: const Key('findYourVibe'),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: HuntrColors.orange.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3A1A08), Color(0xFF1C130E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                      child: Row(children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: Color(0xFF241812),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: HuntrColors.orange, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Find your vibe',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              SizedBox(height: 2),
                              Text('People near you who want the same',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: HuntrColors.muted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // overlapping faces
                        SizedBox(
                          width: 36.0 + 24 * (faces.length - 1),
                          height: 36,
                          child: Stack(children: [
                            for (var i = 0; i < faces.length; i++)
                              Positioned(
                                left: 24.0 * i,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: HuntrColors.orange, width: 1.5),
                                  ),
                                  child: Avatar(
                                      profile: faces[i],
                                      size: 33,
                                      showOnline: false),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _edge),
                          ),
                          child:
                              const Icon(Icons.chevron_right_rounded, size: 22),
                        ),
                      ]),
                    ),
                  ),
                ),
                if (!touch) ...[
                  const VerticalDivider(width: 1, thickness: 1, color: _edge),
                  Tooltip(
                    message: 'Hide until you turn it back on in Settings',
                    child: InkWell(
                      key: const Key('hideVibeBanner'),
                      onTap: onHide,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.visibility_off_outlined, size: 24),
                            SizedBox(height: 4),
                            Text('Hide',
                                style: TextStyle(color: HuntrColors.muted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!touch) return banner;
    return Dismissible(
      key: const Key('dismissVibeBanner'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onHide(),
      child: banner,
    );
  }
}
