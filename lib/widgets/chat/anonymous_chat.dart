import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../screens/agreement_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/messaging_state.dart';
import '../../theme.dart';
import '../anonymous_avatar.dart';
import '../avatar.dart';

/// Above an anonymous conversation: where the reveal request stands, for
/// whichever side I am. The anonymous side answers a pending one here.
class RevealBanner extends StatelessWidget {
  const RevealBanner({
    super.key,
    required this.anonymous,
    required this.reveal,
    this.busy = false,
    this.onAccept,
    this.onDecline,
  });

  final AnonymousInfo anonymous;
  final RevealRequest reveal;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// "2d 5h left" until a pending request expires.
  static String? timeLeft(DateTime? expiresAt, DateTime now) {
    if (expiresAt == null) return null;
    final left = expiresAt.difference(now);
    if (left.isNegative) return 'Ending soon';
    if (left.inDays > 0) return '${left.inDays}d ${left.inHours % 24}h left';
    if (left.inHours > 0) return '${left.inHours}h left';
    return '${left.inMinutes.clamp(1, 59)}m left';
  }

  @override
  Widget build(BuildContext context) {
    final mine = anonymous.iAmAnonymous;
    final (IconData icon, String title, String text) = switch (reveal.status) {
      RevealStatus.pending when mine => (
          Icons.visibility_outlined,
          'Someone’s curious about you 👀',
          'They’d love to know who’s behind ${anonymous.name}. Show your '
              'profile to keep the chat going, or unmatch and stay a mystery. '
              'No pressure, it’s totally your call 💛'
        ),
      RevealStatus.pending => (
          Icons.hourglass_top_rounded,
          'Fingers crossed 🤞',
          'Your request is on its way. We’ll let you know as soon as '
              '${anonymous.name} answers.'
        ),
      RevealStatus.declined when mine => (
          Icons.lock_outline_rounded,
          'Your secret’s safe 🤫',
          'You stayed anonymous. This chat has ended, and your identity stays '
              'private.'
        ),
      RevealStatus.declined => (
          Icons.lock_outline_rounded,
          '${anonymous.name} wants to stay a mystery',
          'That’s okay, it happens 💛 This chat has ended. You’ll find them in '
              'Unmatched users if you change your mind.'
        ),
      RevealStatus.expired when mine => (
          Icons.timer_off_outlined,
          'Time ran out ⏳',
          'No worries, you stayed anonymous. This chat has ended.'
        ),
      RevealStatus.expired => (
          Icons.timer_off_outlined,
          'No answer this time',
          '${anonymous.name} didn’t get back to you in time, so this chat has '
              'ended. Plenty more people to meet 🌟'
        ),
      RevealStatus.accepted => (
          Icons.check_circle_outline_rounded,
          'Mask off 🎉',
          'You can keep chatting in Direct.'
        ),
    };
    final pending = reveal.status == RevealStatus.pending;
    final answering = mine && pending;
    final left = pending ? timeLeft(reveal.expiresAt, DateTime.now()) : null;

    final header = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HuntrColors.orange.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: HuntrColors.orange, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              if (left != null)
                Container(
                  key: const Key('revealTimeLeft'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.schedule_rounded,
                        size: 12, color: HuntrColors.muted),
                    const SizedBox(width: 4),
                    Text(left,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: HuntrColors.muted)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(text,
              style: const TextStyle(
                  color: HuntrColors.muted, fontSize: 13, height: 1.35)),
          if (answering) ...[
            const SizedBox(height: 4),
            const Text(
                'The chat pauses until you decide. If you don’t answer within '
                '3 days, you’ll be unmatched and stay anonymous.',
                style: TextStyle(
                    color: HuntrColors.muted, fontSize: 12, height: 1.35)),
          ],
        ]),
      ),
    ]);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          key: Key('revealBanner-${reveal.status.name}'),
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: answering
                  ? const [Color(0xFF2E1709), Color(0xFF1A1411)]
                  : const [Color(0xFF1C1612), Color(0xFF151518)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: HuntrColors.orange
                    .withValues(alpha: answering ? 0.5 : 0.22)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            if (answering) ...[
              const SizedBox(height: 14),
              _AnswerButtons(
                  busy: busy, onAccept: onAccept, onDecline: onDecline),
            ],
          ]),
        ),
      ),
    );
  }
}

/// "Unmatch" and "Show my profile": side by side, or stacked (the
/// main one first) when there's no room.
class _AnswerButtons extends StatelessWidget {
  const _AnswerButtons({required this.busy, this.onAccept, this.onDecline});

  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    const height = 46.0;
    const shape = StadiumBorder();
    const textStyle = TextStyle(
        fontFamily: huntrFontFamily,
        fontSize: 14.5,
        fontWeight: FontWeight.w700);
    final decline = OutlinedButton.icon(
      key: const Key('declineReveal'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(height),
        shape: shape,
        textStyle: textStyle,
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
      ),
      onPressed: busy ? null : onDecline,
      icon: const Icon(Icons.person_remove_outlined, size: 18),
      label: const Text('Unmatch'),
    );
    final accept = DecoratedBox(
      decoration: const ShapeDecoration(
          gradient: HuntrColors.accentGradient, shape: shape),
      child: FilledButton.icon(
        key: const Key('acceptReveal'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(height),
          shape: shape,
          textStyle: textStyle,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          disabledForegroundColor: Colors.black54,
          shadowColor: Colors.transparent,
        ),
        onPressed: busy ? null : onAccept,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('Show my profile'),
      ),
    );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 400) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accept,
              const SizedBox(height: 8),
              decline,
            ]);
      }
      return Row(children: [
        Expanded(child: decline),
        const SizedBox(width: 10),
        Expanded(child: accept),
      ]);
    });
  }
}

/// In place of the message box when I can't write in an anonymous chat.
class AnonymousClosedBar extends StatelessWidget {
  const AnonymousClosedBar({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('anonymousClosedBar'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded,
              size: 18, color: HuntrColors.muted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: HuntrColors.muted))),
        ]),
      ),
    );
  }
}

/// An anonymous chat that became a direct one somewhere else (merged into
/// the chat we already had).
class MovedToDirectBar extends StatelessWidget {
  const MovedToDirectBar({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: FilledButton.icon(
          key: const Key('openDirectChat'),
          onPressed: onOpen,
          icon: const Icon(Icons.forum_outlined),
          label: const Text('Continue in Direct'),
        ),
      ),
    );
  }
}

/// Before the first anonymous message: how it works, for the anonymous side.
class AnonymousIntro extends StatelessWidget {
  const AnonymousIntro({super.key, required this.anonymous, required this.to});

  final AnonymousInfo anonymous;
  final String to;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // the animal they'll see me as
            SizedBox(
              width: 96,
              height: 96,
              child: AnonymousArt(
                  key: const Key('anonymousIntroAvatar'),
                  animal: anonymous.avatar,
                  radius: 48,
                  size: 96),
            ),
            const SizedBox(height: 14),
            Text('Hi, ${anonymous.name}! 👋',
                key: const Key('anonymousIntro'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'You’re in disguise 🎭 ${to.isEmpty ? 'They' : to} will only see '
              '${anonymous.name}, never your name, photos or profile. Break '
              'the ice with a message. Photos, albums and locations can wait '
              'until you’re ready to meet for real.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: HuntrColors.muted),
            ),
            // the rules anonymity doesn't change
            if (ServicesScope.agreementsOf(context) case final agreements?) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('communityGuidelinesLink'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AgreementScreen.communityGuidelines(
                        agreements: agreements))),
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: const Text('Community Guidelines'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// In the chat where it happened: the anonymous sender showed who they are.
/// [name] is the anonymous name they had; [person] who they turned out to
/// be (for me, the one who asked) or, for them, whom they showed it to.
class RevealedCard extends StatelessWidget {
  const RevealedCard({
    super.key,
    required this.name,
    required this.fromMe,
    required this.person,
    this.avatar,
    this.onViewProfile,
  });

  final String name;

  /// The animal they were shown as.
  final String? avatar;

  /// I'm the one who showed my profile.
  final bool fromMe;
  final Profile person;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    final who = person.name.isEmpty ? 'them' : person.name;
    return Center(
      child: Container(
        key: const Key('revealedCard'),
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A160B), Color(0xFF151214)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.45)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            // the animal they were, then who they are
            SizedBox(
              width: 40,
              height: 40,
              child: avatar == null
                  ? const Icon(Icons.theater_comedy_rounded,
                      color: HuntrColors.orange)
                  : AnonymousArt(animal: avatar!, radius: 20, size: 40),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded,
                size: 16, color: HuntrColors.muted),
            const SizedBox(width: 6),
            Avatar(profile: person, size: 40, showOnline: false),
          ]),
          const SizedBox(height: 10),
          Text(
            fromMe ? 'Mask off! 🎉' : 'Surprise! $name revealed themselves 🎉',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text.rich(
            fromMe
                ? TextSpan(children: [
                    TextSpan(text: '$who now knows '),
                    TextSpan(
                        text: name,
                        style: const TextStyle(
                            color: HuntrColors.orange,
                            fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' was you. Have fun chatting!'),
                  ])
                : TextSpan(children: [
                    TextSpan(
                        text: name,
                        style: const TextStyle(
                            color: HuntrColors.orange,
                            fontWeight: FontWeight.w700)),
                    TextSpan(text: ' is $who! Say hi properly 👋'),
                  ]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted, fontSize: 13),
          ),
          if (!fromMe && onViewProfile != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('revealedViewProfile'),
              onPressed: onViewProfile,
              icon: const Icon(Icons.person_outline_rounded, size: 18),
              label: const Text('View profile'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Asks (after confirming) the anonymous sender of this chat to show their
/// profile, and says how it went. The updated anonymous profile, or null
/// when it wasn't sent. [onSending] is told while it's being sent.
Future<AnonymousProfile?> askToSeeProfile(BuildContext context,
    {required int conversationId,
    required String name,
    ValueChanged<bool>? onSending}) async {
  final messaging = MessagingScope.read(context);
  if (messaging == null) return null;
  final messenger = ScaffoldMessenger.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Curious who it is? 👀'),
      content: Text('We’ll ask $name if they’d like to show you who they '
          'are. The chat pauses while they decide. If they don’t answer within '
          '3 days, the chat ends and they stay a mystery.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            key: const Key('confirmRequestReveal'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ask them')),
      ],
    ),
  );
  if (yes != true) return null;
  onSending?.call(true);
  try {
    final updated = await messaging.requestReveal(conversationId);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          key: Key('revealRequested'),
          content:
              Text('Request sent! 🤞 We’ll let you know when they answer.')));
    return updated;
  } on BackendException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return null;
  } finally {
    onSending?.call(false);
  }
}

/// "Unmatch [name]?" - true when confirmed.
Future<bool> confirmUnmatch(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unmatch ${name.isEmpty ? 'them' : name}?'),
        content: const Text('This chat will end for both of you, and you '
            'won’t see each other in Explore. Changed your mind? No problem, you '
            'can undo it anytime in Settings → Unmatched users.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('confirmUnmatch'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Unmatch')),
        ],
      ),
    ) ==
    true;

/// In the chat where it was asked: the recipient wants to see who the
/// anonymous sender is (answered in the banner above the chat).
class RevealRequestCard extends StatelessWidget {
  const RevealRequestCard({super.key, required this.fromMe});

  /// I'm the one who asked.
  final bool fromMe;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('revealRequestCard'),
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HuntrColors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.visibility_outlined,
              size: 18, color: HuntrColors.orange),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fromMe
                  ? 'You asked to see who they are 👀'
                  : 'They’re curious who you are 👀',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }
}
