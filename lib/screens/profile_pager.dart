import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_screen.dart';

/// Profiles from Explore, one after another: swipe right for the next
/// person, left for the previous one (a mouse drag or the arrow keys on
/// desktop). The order is the list as it was when it was opened, so a
/// refresh behind it doesn't reshuffle. A swipe that starts on the photos
/// moves through that person's photos instead.
class ProfilePager extends StatefulWidget {
  const ProfilePager(
      {super.key,
      required this.profileIds,
      required this.initialIndex,
      this.onShow});

  final List<String> profileIds;
  final int initialIndex;

  /// A profile came into view (e.g. load all their photos).
  final ValueChanged<String>? onShow;

  @override
  State<ProfilePager> createState() => _ProfilePagerState();
}

class _ProfilePagerState extends State<ProfilePager> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final page = (_pages.page ?? widget.initialIndex.toDouble()).round();
    final target = page + delta;
    if (target < 0 || target >= widget.profileIds.length) return;
    _pages.animateToPage(target,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: ScrollConfiguration(
          // a mouse can drag between profiles too
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          }),
          child: PageView.builder(
            key: const Key('profilePager'),
            controller: _pages,
            // swiping right brings the next person in
            reverse: true,
            itemCount: widget.profileIds.length,
            onPageChanged: (i) => widget.onShow?.call(widget.profileIds[i]),
            itemBuilder: (_, i) => ProfileScreen(
                key: ValueKey('profile-${widget.profileIds[i]}'),
                profileId: widget.profileIds[i]),
          ),
        ),
      ),
    );
  }
}
