import 'package:flutter/material.dart';

import '../theme.dart';

/// The blue of the check (as on X and Instagram).
const verifiedBlue = Color(0xFF1D9BF0);

/// The blue check by a verified person's name: our team confirmed who they
/// are from documents they sent. Hovering says so briefly; tapping it (when
/// [interactive]) explains it in full. Lists leave it not [interactive], so
/// a tap opens the profile as usual.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge(
      {super.key, this.size = 20, this.name, this.interactive = true});

  final double size;

  /// Whose it is, for the explanation ("Sam is verified").
  final String? name;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final check = Icon(Icons.verified_rounded,
        key: const Key('verifiedBadge'),
        size: size,
        color: verifiedBlue,
        semanticLabel: 'Verified');
    return Tooltip(
      message: 'Verified: identity confirmed by HUNTR',
      child: !interactive
          ? check
          : InkResponse(
              key: const Key('verifiedBadgeButton'),
              radius: size,
              onTap: () => showVerifiedInfo(context, name: name),
              child: check,
            ),
    );
  }
}

/// What the blue check means, in plain words.
Future<void> showVerifiedInfo(BuildContext context, {String? name}) {
  final who = name == null || name.trim().isEmpty ? 'This person' : name.trim();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // as tall as it needs (it scrolls on a short screen)
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        key: const Key('verifiedInfo'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_rounded, size: 56, color: verifiedBlue),
          const SizedBox(height: 12),
          Text('$who is verified',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'They sent us an ID document and our team checked that it '
            'matches them, so they are who they say they are.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 16),
          const _Point(
              icon: Icons.shield_outlined,
              text: 'We verify people to keep out fake accounts and anyone '
                  'pretending to be someone else.'),
          const _Point(
              icon: Icons.lock_outline_rounded,
              text: 'Their documents stay private: nobody on HUNTR sees '
                  'them.'),
          const _Point(
              icon: Icons.handshake_outlined,
              text: 'A blue check confirms who someone is, not how they '
                  'behave, so still chat and meet safely.'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: verifiedBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder()),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: verifiedBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: HuntrColors.muted, fontSize: 14, height: 1.4)),
          ),
        ]),
      );
}
