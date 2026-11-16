import 'package:flutter/material.dart';

import '../state/tap_state.dart';
import '../theme.dart';
import 'avatar.dart';

/// Beside the Taps button for a moment when someone taps me or views my
/// profile: their photo (a blank portrait when it isn't known who) and
/// what happened (an eye: viewed; a hand: tapped). Tapping it opens them.
class ActivityBubble extends StatelessWidget {
  const ActivityBubble(
      {super.key,
      required this.activity,
      required this.visible,
      required this.onTap,
      this.small = false});

  final TapActivity activity;

  /// Smaller (a phone's bottom bar); full size beside the sidebar.
  final bool small;

  /// Fading in (true) or out.
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final person = activity.person;
    final name = person == null || person.name.isEmpty ? null : person.name;
    final said = activity.viewed
        ? '${name ?? 'Someone'} viewed your profile'
        : '${name ?? 'Someone'} tapped you';
    final photo = small ? 30.0 : 42.0;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: AnimatedScale(
        scale: visible ? 1 : 0.85,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: Semantics(
          button: true,
          label: said,
          child: Tooltip(
            message: said,
            child: Material(
              key: const Key('activityBubble'),
              color: HuntrColors.surfaceHigh,
              // no shadow: just a light edge
              elevation: 0,
              shape: StadiumBorder(
                  side:
                      BorderSide(color: Colors.white.withValues(alpha: 0.12))),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                  padding: small
                      ? const EdgeInsets.fromLTRB(3, 3, 9, 3)
                      : const EdgeInsets.fromLTRB(5, 5, 12, 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    // who: their photo, or a blank portrait
                    person == null
                        ? Container(
                            key: const Key('activityBubbleBlank'),
                            width: photo,
                            height: photo,
                            decoration: const BoxDecoration(
                                color: HuntrColors.night,
                                shape: BoxShape.circle),
                            child: Icon(Icons.person_rounded,
                                color: HuntrColors.muted, size: photo * 0.66),
                          )
                        : Avatar(
                            profile: person, size: photo, showOnline: false),
                    SizedBox(width: small ? 6 : 10),
                    // what: viewed (an eye) or tapped (a hand)
                    Icon(
                        activity.viewed
                            ? Icons.visibility_rounded
                            : Icons.waving_hand_rounded,
                        key: Key(activity.viewed
                            ? 'activityBubbleViewed'
                            : 'activityBubbleTapped'),
                        color:
                            activity.viewed ? Colors.white : HuntrColors.orange,
                        size: small ? 16 : 22),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
