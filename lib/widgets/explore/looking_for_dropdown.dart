import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../pill_chip.dart';

/// Explore's "Looking for" quick filter: one chip that opens a list of the
/// choices, each with a checkbox. Several can be ticked; the list stays open
/// until a tap outside it.
class LookingForDropdown extends StatelessWidget {
  const LookingForDropdown(
      {super.key, required this.chosen, required this.onChanged});

  final Set<LookingFor> chosen;
  final ValueChanged<Set<LookingFor>> onChanged;

  /// "Looking for", the one choice, or "Looking for (2)".
  String get _label => switch (chosen.length) {
        0 => 'Looking for',
        1 => chosen.first.label,
        final n => 'Looking for ($n)',
      };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(HuntrColors.night),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF353944)))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final l in LookingFor.values)
          CheckboxMenuButton(
            key: Key('lookingForOption-${l.name}'),
            value: chosen.contains(l),
            closeOnActivate: false,
            onChanged: (on) {
              final next = {...chosen};
              on == true ? next.add(l) : next.remove(l);
              onChanged(next);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(l.icon, size: 18, color: HuntrColors.muted),
                const SizedBox(width: 10),
                Text(l.label),
              ]),
            ),
          ),
      ],
      builder: (context, menu, _) => PillChip(
        key: const Key('lookingForChip'),
        icon: chosen.length == 1 ? chosen.first.icon : Icons.favorite_border,
        label: _label,
        dropdown: true,
        selected: chosen.isNotEmpty,
        onSelected: (_) => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
