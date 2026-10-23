import 'package:flutter/material.dart';

import '../theme.dart';

class HuntrBottomBarItem {
  const HuntrBottomBarItem(
      {required this.icon,
      required this.label,
      this.selectedIcon,
      this.badge = 0});
  final IconData icon;

  /// Shown while it's the selected tab (a filled version), when given.
  final IconData? selectedIcon;
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
          height: 62,
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
    // five tabs share a phone's width: labels grow only a little with the
    // phone's text size, so they never crowd each other
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1);
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
              // small: five tabs share the width
              width: 40,
              height: 26,
              decoration: BoxDecoration(
                color: selected
                    ? HuntrColors.orange.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Badge(
                isLabelVisible: item.badge > 0,
                label: Text('${item.badge}'),
                child: Icon(
                    selected ? item.selectedIcon ?? item.icon : item.icon,
                    color: color,
                    size: 21),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textScaler: scaler,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
