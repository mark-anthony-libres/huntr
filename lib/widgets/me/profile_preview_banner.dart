import 'package:flutter/material.dart';

import '../../theme.dart';

/// "Preview my profile": a small row; tap to see it as others do.
class ProfilePreviewBanner extends StatelessWidget {
  const ProfilePreviewBanner({super.key, required this.onViewProfile});

  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('viewMyProfile'),
        borderRadius: BorderRadius.circular(14),
        onTap: onViewProfile,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              HuntrColors.orange.withValues(alpha: 0.10),
              HuntrColors.surface,
            ]),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: HuntrColors.orange.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: HuntrColors.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.visibility_outlined,
                  color: HuntrColors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview my profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text('See it the way others do',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
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
