import 'package:flutter/material.dart';
import '../models/models.dart';
import '../screens/chat_screen.dart';
import '../state/app_state.dart';
import '../widgets/share_sheet.dart';

/// Approve [p]'s request after picking which of my albums to send back. Shared with the Chats screen.
Future<void> acceptWithAlbum(BuildContext context, Profile p) async {
  final choice = await showShareSheet(
    context,
    title: 'Accept ${p.name}\'s request',
    subtitle:
        'Pick an album to send to ${p.name}. Their chosen album is sent to you, and the chat opens.',
    actionLabel: 'Accept & share',
    actionIcon: Icons.check_rounded,
  );
  if (choice == null || !context.mounted) return;
  AppScope.read(context).acceptRequest(p, albumId: choice.albumId);
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ChatScreen(profileId: p.id)));
}
