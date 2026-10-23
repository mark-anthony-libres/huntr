import 'package:flutter/material.dart';
import '../../theme.dart';

class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                color: HuntrColors.muted,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}
