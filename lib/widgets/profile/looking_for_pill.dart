import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';

/// One "looking for" choice on a profile: outlined pill with an orange icon.
class LookingForPill extends StatelessWidget {
  const LookingForPill({super.key, required this.choice});

  final LookingFor choice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF3A3B44)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(choice.icon, size: 16, color: HuntrColors.orange),
        const SizedBox(width: 6),
        Text(choice.label,
            style: const TextStyle(fontSize: 13.5, color: Colors.white)),
      ]),
    );
  }
}
