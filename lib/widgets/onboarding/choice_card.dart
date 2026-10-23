import 'package:flutter/material.dart';
import '../../theme.dart';

class ChoiceCard extends StatelessWidget {
  const ChoiceCard(
      {super.key,
      required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? HuntrColors.orange.withValues(alpha: 0.14)
          : HuntrColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? HuntrColors.orange : Colors.transparent,
            width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            Icon(icon,
                color: selected ? HuntrColors.orange : HuntrColors.muted),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? HuntrColors.orange : HuntrColors.muted),
          ]),
        ),
      ),
    );
  }
}
