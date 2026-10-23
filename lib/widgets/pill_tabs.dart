import 'package:flutter/material.dart';

import '../theme.dart';

/// One tab of [PillTabs].
class PillTab {
  const PillTab(
      {required this.key,
      required this.icon,
      required this.label,
      this.badge = 0});

  final Key key;
  final IconData icon;
  final String label;

  /// A count beside the label (hidden at 0).
  final int badge;
}

/// Two (or more) tabs in a rounded bar, the selected one filled orange:
/// Chats' Direct / Anonymous, Taps' Taps / Viewers.
class PillTabs extends StatelessWidget {
  const PillTabs(
      {super.key,
      required this.tabs,
      required this.selected,
      required this.onChanged});

  final List<PillTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(int index, PillTab t) {
      final on = index == selected;
      return Expanded(
        child: Material(
          color: on ? HuntrColors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            key: t.key,
            borderRadius: BorderRadius.circular(22),
            onTap: () => onChanged(index),
            child: SizedBox(
              height: 42,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(t.icon,
                    size: 19, color: on ? Colors.black : HuntrColors.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(t.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.black : Colors.white)),
                ),
                if (t.badge > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: on ? Colors.black : HuntrColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(t.badge > 99 ? '99+' : '${t.badge}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: on ? HuntrColors.orange : Colors.black)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: HuntrColors.border),
      ),
      child: Row(children: [
        for (final (i, t) in tabs.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          tab(i, t),
        ],
      ]),
    );
  }
}
