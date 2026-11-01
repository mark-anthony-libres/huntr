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

/// On the website, from this width (a computer, a tablet) the tabs are a
/// sidebar on the left instead of the bottom bar (the app keeps the bar).
const huntrSideBarMinWidth = 900.0;

/// From this width the sidebar shows each label beside its icon (below it
/// on a narrower one).
const _wideSideBarMinWidth = 1200.0;

/// The same tabs as [HuntrBottomBar], as a sidebar on the left: the logo on
/// top, the selected tab orange in a soft pill.
class HuntrSideBar extends StatelessWidget {
  const HuntrSideBar({
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
    final wide = MediaQuery.sizeOf(context).width >= _wideSideBarMinWidth;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HuntrColors.night,
        border: Border(right: BorderSide(color: HuntrColors.border)),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: wide ? 232 : 88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(wide ? 22 : 0, 22, 0, 26),
                child: Row(
                  mainAxisAlignment:
                      wide ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/huntr_logo.png',
                        key: const Key('sideBarLogo'), height: 40),
                  ],
                ),
              ),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: wide ? 12 : 8, vertical: 3),
                  child: _SideItem(
                    item: items[i],
                    selected: i == selectedIndex,
                    wide: wide,
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

class _SideItem extends StatelessWidget {
  const _SideItem(
      {required this.item,
      required this.selected,
      required this.wide,
      required this.onTap});

  final HuntrBottomBarItem item;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? HuntrColors.orange : HuntrColors.muted;
    final icon = Badge(
      isLabelVisible: item.badge > 0,
      label: Text('${item.badge}'),
      child: Icon(selected ? item.selectedIcon ?? item.icon : item.icon,
          color: color, size: 24),
    );
    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: TextStyle(
        color: selected ? HuntrColors.orange : Colors.white,
        fontSize: wide ? 16 : 11.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? HuntrColors.orange.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('sideBar-${item.label}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: wide
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                : const EdgeInsets.symmetric(vertical: 10),
            child: wide
                ? Row(children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: label),
                  ])
                : Column(children: [icon, const SizedBox(height: 4), label]),
          ),
        ),
      ),
    );
  }
}
