import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/anonymous_avatar.dart';
import '../widgets/chat/anonymous_chat.dart';
import '../widgets/me/section_states.dart';
import '../widgets/avatar.dart' show OnlineDot;

/// Someone writing to me anonymously, as I may see them: their anonymous
/// name and animal, whether they're online, roughly how far away (if they
/// share it), and two actions - ask to see their real profile, or report
/// them. Everything comes from the backend by conversation; their real
/// profile, photos and id are never here.
class AnonymousProfileScreen extends StatefulWidget {
  const AnonymousProfileScreen({super.key, required this.conversationId});

  final int conversationId;

  @override
  State<AnonymousProfileScreen> createState() => _AnonymousProfileScreenState();
}

class _AnonymousProfileScreenState extends State<AnonymousProfileScreen> {
  AnonymousProfile? _profile;
  String? _error;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final messaging = MessagingScope.read(context);
    if (messaging == null) return;
    setState(() => _error = null);
    try {
      final profile = await messaging.anonymousProfile(widget.conversationId);
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    }
  }

  Future<void> _removeUnmatch() async {
    final messaging = MessagingScope.read(context)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _requesting = true);
    try {
      await messaging.removeUnmatch(
          anonymousConversationId: widget.conversationId);
      messenger.showSnackBar(const SnackBar(
          content: Text('Welcome back! 💛 They’re off your Unmatched list.')));
      navigator.pop(true);
    } on BackendException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _requestReveal(AnonymousProfile profile) async {
    final updated = await askToSeeProfile(context,
        conversationId: widget.conversationId,
        name: profile.name, onSending: (sending) {
      if (mounted) setState(() => _requesting = sending);
    });
    if (mounted && updated != null) setState(() => _profile = updated);
  }

  Future<void> _report(AnonymousProfile profile) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportSheet(
          conversationId: widget.conversationId,
          name: profile.name,
          messaging: MessagingScope.read(context)!),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            key: Key('reportSent'),
            content: Text('Thank you for looking out 💛 We’ll take a look, '
                'and they won’t know it was you.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: LoadFailedCard(
            title: 'Couldn’t load this profile',
            message: _error!,
            onRetry: _load),
      );
    } else if (profile == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // a phone-width column, also on wide screens
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(profile: profile),
                  const SizedBox(height: 20),
                  const _HowItWorks(),
                  const SizedBox(height: 24),
                  // on my Unmatched list: only taking them off it
                  if (profile.unmatched)
                    FilledButton.icon(
                      key: const Key('removeUnmatchButton'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54)),
                      onPressed: _requesting ? null : _removeUnmatch,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Remove from Unmatch List'),
                    )
                  else
                    _RevealAction(
                      profile: profile,
                      busy: _requesting,
                      onRequest: () => _requestReveal(profile),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      key: const Key('reportAnonymous'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF8A80)),
                      onPressed: () => _report(profile),
                      icon: const Icon(Icons.flag_outlined, size: 19),
                      label: Text('Report ${profile.name}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      key: const Key('anonymousProfile'),
      appBar: AppBar(title: const Text('Anonymous profile')),
      body: body,
    );
  }
}

/// The animal, name and status, on a warm card.
class _Hero extends StatelessWidget {
  const _Hero({required this.profile});

  final AnonymousProfile profile;

  @override
  Widget build(BuildContext context) {
    final online = profile.online && !profile.blocked;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A160B), Color(0xFF161210), Color(0xFF111114)],
          stops: [0, 0.55, 1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        // the animal, glowing
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: HuntrColors.orange.withValues(alpha: 0.35),
                  blurRadius: 36,
                  spreadRadius: 2),
            ],
          ),
          child: AnonymousArt(animal: profile.avatar, radius: 66, size: 132),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: HuntrColors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.theater_comedy_outlined,
                size: 15, color: HuntrColors.orange),
            SizedBox(width: 6),
            Text('ANONYMOUS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: HuntrColors.orange)),
          ]),
        ),
        const SizedBox(height: 10),
        Text(profile.name,
            key: const Key('anonymousName'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              leading: online
                  ? const OnlineDot(size: 9)
                  : const Icon(Icons.circle_outlined,
                      size: 10, color: HuntrColors.muted),
              label: online ? 'Online now' : 'Offline',
              color: online ? HuntrColors.online : HuntrColors.muted,
            ),
            if (profile.distanceKm case final km?)
              _Pill(
                key: const Key('anonymousDistance'),
                leading: const Icon(Icons.near_me_rounded,
                    size: 14, color: HuntrColors.muted),
                label: 'About $km km away',
                color: Colors.white70,
              ),
          ],
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {super.key,
      required this.leading,
      required this.label,
      required this.color});

  final Widget leading;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        leading,
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// What anonymous means here, in three lines.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: HuntrColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: HuntrColors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(text,
                        style: const TextStyle(
                            color: HuntrColors.muted, fontSize: 13)),
                  ]),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(children: [
        row(Icons.visibility_off_outlined, 'Private for now',
            'Their name, photos and profile stay private.'),
        row(
            Icons.chat_bubble_outline_rounded,
            'Just text',
            'Anonymous chats are for messages only. Photos, videos, albums '
                'and locations can wait.'),
        row(Icons.how_to_reg_outlined, 'Curious who it is?',
            'You can ask to see their profile. It’s up to them to share it.'),
      ]),
    );
  }
}

/// "Request to see profile", or where that request stands.
class _RevealAction extends StatelessWidget {
  const _RevealAction(
      {required this.profile, required this.busy, required this.onRequest});

  final AnonymousProfile profile;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final status = profile.reveal?.status;
    if (status == null) {
      final enabled = profile.canRequestReveal && !busy;
      return Opacity(
        opacity: enabled || busy ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
              gradient: HuntrColors.accentGradient,
              borderRadius: BorderRadius.all(Radius.circular(30))),
          child: FilledButton.icon(
            key: const Key('requestReveal'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.black,
              minimumSize: const Size.fromHeight(54),
              textStyle: const TextStyle(
                  fontFamily: huntrFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            onPressed: enabled ? onRequest : null,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.visibility_outlined),
            label: const Text('Request to see profile'),
          ),
        ),
      );
    }
    final (IconData icon, String title, String text) = switch (status) {
      RevealStatus.pending => (
          Icons.hourglass_top_rounded,
          'Fingers crossed 🤞',
          'We’ll let you know as soon as they answer. The chat pauses until then.'
        ),
      RevealStatus.accepted => (
          Icons.check_circle_outline_rounded,
          'Mask off 🎉',
          'They revealed who they are!'
        ),
      RevealStatus.declined => (
          Icons.lock_outline_rounded,
          'They want to stay a mystery',
          'That’s okay, it happens 💛 You’ll find them in Unmatched users.'
        ),
      RevealStatus.expired => (
          Icons.timer_off_outlined,
          'No answer this time',
          'They didn’t get back to you in time, so this chat has ended.'
        ),
    };
    return Container(
      key: Key('revealStatus-${status.name}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuntrColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        Icon(icon, color: HuntrColors.orange),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(text,
                style: const TextStyle(color: HuntrColors.muted, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

/// Why I'm reporting them, and optionally more.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet(
      {required this.conversationId,
      required this.name,
      required this.messaging});

  final int conversationId;
  final String name;
  final MessagingState messaging;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = {
    'spam': 'Spam or scam',
    'harassment': 'Harassment or threats',
    'inappropriate': 'Inappropriate messages',
    'other': 'Something else',
  };

  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.messaging.reportAnonymous(widget.conversationId,
          reason: _reason!, details: _details.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Your report could not be sent. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Report ${widget.name}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                  'You’re safe here 💛 Your report is private, and they won’t know it was you.',
                  style: TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 10),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(children: [
                  for (final MapEntry(:key, :value) in _reasons.entries)
                    RadioListTile<String>(
                      key: Key('reportReason-$key'),
                      value: key,
                      title: Text(value),
                      contentPadding: EdgeInsets.zero,
                    ),
                ]),
              ),
              TextField(
                key: const Key('reportDetails'),
                controller: _details,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Want to tell us more? (optional)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFFF9B8A))),
                ),
              FilledButton(
                key: const Key('sendReport'),
                onPressed: _reason == null || _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send report'),
              ),
            ]),
      ),
    );
  }
}
