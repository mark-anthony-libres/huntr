import 'package:flutter/material.dart';

import '../theme.dart';

/// A pill chip with an icon: orange-filled when selected.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final IconData? icon;

  /// Instead of [icon], e.g. an online dot.
  final Widget? leading;
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : HuntrColors.muted;
    return FilterChip(
      avatar:
          leading ?? (icon == null ? null : Icon(icon, size: 18, color: color)),
      label: Text(label),
      labelStyle: TextStyle(
          fontFamily: huntrFontFamily,
          color: selected ? Colors.white : const Color(0xFFD5D8E0),
          fontWeight: FontWeight.w600),
      selected: selected,
      showCheckmark: false,
      selectedColor: HuntrColors.orange,
      backgroundColor: HuntrColors.night,
      shape: StadiumBorder(
          side: BorderSide(
              color: selected ? HuntrColors.orange : const Color(0xFF353944),
              width: 1.2)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      onSelected: onSelected,
    );
  }
}
