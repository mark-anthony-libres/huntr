import 'package:flutter/material.dart';

import '../theme.dart';

class HuntrBottomBarItem {
  const HuntrBottomBarItem(
      {required this.icon, required this.label, this.badge = 0});
  final IconData icon;
  final String label;

  /// Shown as a count on the icon when above zero.
  final int badge;
}

/// Bottom navigation: the selected tab is orange, its icon in a soft pill.
class HuntrBottomBar extends StatelessWidget {
  const HuntrBottomBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<HuntrBottomBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HuntrColors.night,
        border: Border(top: BorderSide(color: HuntrColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BarItem(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem(
      {required this.item, required this.selected, required this.onTap});

  final HuntrBottomBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? HuntrColors.orange : HuntrColors.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // the selected tab's icon sits in a soft orange pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 64,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? HuntrColors.orange.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Badge(
                isLabelVisible: item.badge > 0,
                label: Text('${item.badge}'),
                child: Icon(item.icon, color: color, size: 24),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
