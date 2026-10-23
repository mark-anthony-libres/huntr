import 'package:flutter/material.dart';

import '../../theme.dart';

/// "See how others see your profile": tap to open the preview.
class ProfilePreviewBanner extends StatelessWidget {
  const ProfilePreviewBanner({super.key, required this.onViewProfile});

  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('viewMyProfile'),
        borderRadius: BorderRadius.circular(20),
        onTap: onViewProfile,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              HuntrColors.orange.withValues(alpha: 0.10),
              HuntrColors.surface,
            ]),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: HuntrColors.orange.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: HuntrColors.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.visibility_outlined,
                  color: HuntrColors.orange, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('See how others see your profile',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Preview your profile as it appears to other users.',
                      style: TextStyle(color: HuntrColors.muted, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: HuntrColors.muted),
          ]),
        ),
      ),
    );
  }
}
