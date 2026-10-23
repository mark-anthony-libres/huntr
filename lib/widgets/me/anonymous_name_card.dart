import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import '../nearby/nearby_post_card.dart' show NearbyAvatar;

/// On my profile (only I see it): the anonymous name I go by in anonymous
/// chats and Threads, and Change - a new random one from now on (what I
/// already wrote keeps the old one). The backend makes and keeps them.
class AnonymousNameCard extends StatefulWidget {
  const AnonymousNameCard({super.key});

  @override
  State<AnonymousNameCard> createState() => _AnonymousNameCardState();
}

class _AnonymousNameCardState extends State<AnonymousNameCard> {
  bool _changing = false;

  Future<void> _change() async {
    final app = AppScope.read(context);
    final profiles = ServicesScope.profilesOf(context);
    final token = app.sessionToken;
    if (profiles == null || token == null || _changing) return;
    final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Get a new anonymous name?'),
            content: const Text(
                "You'll get a new random name. Your anonymous chats show it "
                'right away; threads you already wrote keep your current one.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  key: const Key('anonymousNameConfirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Change')),
            ],
          ),
        ) ??
        false;
    if (!sure || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final messaging = MessagingScope.read(context);
    setState(() => _changing = true);
    try {
      final name = await profiles.changeAnonymousName(token);
      app.anonymousName = name;
      // my anonymous chats show it now: their list again
      unawaited(messaging?.refresh());
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("You're ${name.name} now.")));
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text(error is BackendException
              ? error.message
              : "Your name couldn't be changed. Try again.")));
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = AppScope.of(context).anonymousName;
    if (name == null) return const SizedBox.shrink();
    return Container(
      key: const Key('anonymousNameCard'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HuntrColors.border),
      ),
      child: Row(children: [
        NearbyAvatar(animal: name.avatar, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your anonymous name',
                style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
            const SizedBox(height: 2),
            Text(name.name,
                key: const Key('anonymousName'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text('In anonymous chats and Threads. Only you see it.',
                style: TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
          ]),
        ),
        TextButton.icon(
          key: const Key('anonymousNameChange'),
          onPressed: _changing ? null : _change,
          icon: _changing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Change'),
        ),
      ]),
    );
  }
}
