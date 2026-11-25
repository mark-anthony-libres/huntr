import 'package:flutter/material.dart';

import '../../screens/guest_link_screen.dart';
import '../../state/guest_chats_state.dart';
import '../../theme.dart';

/// Opens my guest link (to share on My Day or a story), saying how many
/// guest chats are open. On Me and my anonymous profile.
class GuestLinkTile extends StatelessWidget {
  const GuestLinkTile({super.key});

  @override
  Widget build(BuildContext context) {
    final state = GuestChatsScope.of(context);
    if (state == null) return const SizedBox.shrink();
    final open = state.chats.length;
    return Material(
      color: HuntrColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: HuntrColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const Key('openGuestLink'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        minVerticalPadding: 14,
        leading: Icon(Icons.link_rounded, color: HuntrColors.orange),
        title: const Text('Guest link',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
              open == 0
                  ? 'Share on My Day. People without HUNTR chat with you '
                      'anonymously.'
                  : 'Share on My Day · $open guest '
                      '${open == 1 ? 'chat' : 'chats'} open',
              style: const TextStyle(color: HuntrColors.muted, height: 1.4)),
        ),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: HuntrColors.muted),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const GuestLinkScreen())),
      ),
    );
  }
}
