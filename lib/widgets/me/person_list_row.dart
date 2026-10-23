import 'package:flutter/material.dart';

import '../../theme.dart';
import '../anonymous_avatar.dart';
import '../network_photo.dart';

/// One person in a list of people I manage (Blocked users, Unmatched users):
/// their photo (or, someone I only know anonymously, their animal), name, a
/// status line and one action button. Tapping the row opens [onTap].
class PersonListRow extends StatelessWidget {
  const PersonListRow({
    super.key,
    required this.name,
    required this.status,
    required this.actionLabel,
    this.photoUrl,
    this.anonymousAvatar,
    this.statusKey,
    this.actionKey,
    this.onAction,
    this.busy = false,
    this.onTap,
  });

  final String name;
  final String? photoUrl;

  /// Their animal, when they're anonymous to me.
  final String? anonymousAvatar;
  final String status;
  final Key? statusKey;
  final String actionLabel;
  final Key? actionKey;

  /// Null: the action isn't available yet.
  final VoidCallback? onAction;

  /// The action is running (its button waits).
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HuntrColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: anonymousAvatar != null
                    ? AnonymousArt(
                        animal: anonymousAvatar!, radius: 24, size: 48)
                    : photoUrl == null
                        ? const ColoredBox(
                            color: HuntrColors.surfaceHigh,
                            child: Icon(Icons.person_rounded,
                                color: HuntrColors.muted))
                        : NetworkPhoto(photoUrl!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Someone' : name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(status,
                        key: statusKey,
                        style: const TextStyle(
                            color: HuntrColors.muted, fontSize: 13)),
                  ]),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: actionKey,
              onPressed: busy ? null : onAction,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(actionLabel),
            ),
          ]),
        ),
      ),
    );
  }
}
