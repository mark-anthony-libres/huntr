import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../photos/cached_photo_image.dart';

/// The user's own card at the top of Me: photo with an orange ring, name,
/// age and bio on a warm glow, and the edit button.
class MeProfileCard extends StatelessWidget {
  const MeProfileCard({
    super.key,
    required this.name,
    required this.age,
    required this.bio,
    required this.photo,
    required this.placeholder,
    required this.showOnline,
    required this.onEdit,
  });

  final String name;
  final int age;
  final String bio;

  /// My default photo; null shows [placeholder].
  final ProfilePhoto? photo;

  /// Shown until I have a photo (my character avatar).
  final Widget placeholder;
  final bool showOnline;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 420;
    // Below this the button is just the pencil, so the name has room.
    final compactEdit = width < 480;
    final avatarSize = narrow ? 88.0 : 108.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        gradient: HuntrColors.glowGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: HuntrColors.ember.withValues(alpha: 0.28),
            blurRadius: 32,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RingedAvatar(
              photo: photo,
              placeholder: placeholder,
              size: avatarSize,
              online: showOnline),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                      '$name, $age',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: narrow ? 22 : 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The name takes the rest of the row, keeping this on the
                  // right; the cap lets its label shorten instead of overflow.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: _EditButton(compact: compactEdit, onPressed: onEdit),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  bio.isEmpty
                      ? 'Add a short bio so people know what to say'
                      : bio,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Edit profile" pill; just the pencil on narrow phones.
class _EditButton extends StatelessWidget {
  const _EditButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Edit profile',
      excludeFromSemantics: !compact,
      // Solid and high-contrast on the orange card, so it reads as tappable.
      child: Material(
        color: HuntrColors.night,
        elevation: 3,
        shadowColor: Colors.black54,
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.edit,
                  color: HuntrColors.orange,
                  size: 18,
                  semanticLabel: compact ? 'Edit profile' : null),
              if (!compact) ...[
                const SizedBox(width: 8),
                const Flexible(
                  child: Text('Edit profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({
    required this.photo,
    required this.placeholder,
    required this.size,
    required this.online,
  });

  final ProfilePhoto? photo;
  final Widget placeholder;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Fills the whole box, so the online dot sits on the ring.
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: HuntrColors.accentGradient,
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: HuntrColors.night),
                child: ClipOval(
                  child: photo == null ? placeholder : CachedPhotoImage(photo!),
                ),
              ),
            ),
          ),
          if (online)
            Positioned(
              right: size * 0.06,
              bottom: size * 0.06,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: HuntrColors.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: HuntrColors.night, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
