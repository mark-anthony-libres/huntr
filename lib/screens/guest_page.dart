import 'dart:async';

import 'package:flutter/material.dart';

import '../flows/guest_join.dart';
import '../services/guest_chat_api.dart';
import '../services/huntr_backend.dart' show BackendException;
import '../services/services_scope.dart';
import '../state/guest_chats_state.dart';
import '../theme.dart';
import '../widgets/anonymous_avatar.dart';
import '../widgets/chat/guest_chat_view.dart';
import 'agreement_screen.dart';

/// A guest link opened in a browser (huntr.online/g/<code>), by someone not
/// on HUNTR: straight into a temporary anonymous chat with its owner (the
/// shared guest chat view), and joining HUNTR to keep talking. The chat
/// itself starts with the guest's first message (or GIF search), so opening
/// the link leaves nothing behind. [onLeave] goes to HUNTR itself (sign up
/// or log in).
class GuestPage extends StatefulWidget {
  const GuestPage(
      {super.key, required this.code, required this.onLeave, this.api});

  final String code;
  final VoidCallback onLeave;

  /// The backend (tests pass their own).
  final GuestChatApi? api;

  @override
  State<GuestPage> createState() => _GuestPageState();
}

class _GuestPageState extends State<GuestPage> {
  late final GuestChatApi _api = widget.api ?? GuestChatApi();
  GuestLinkCard? _card;
  String? _cardError;

  /// The chat's secret, once it started.
  String? _token;
  Future<String>? _starting;
  GuestChatController? _chat;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _chat?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final card = await _api.linkCard(widget.code);
      if (!mounted) return;
      setState(() => _card = card);
      // a chat already open here (a reload): back into it, unless it ended
      // meanwhile (then forgotten: a new one)
      final token = await GuestStore.token(widget.code);
      if (!mounted) return;
      if (token == null) return _open(null);
      try {
        final page = await _api.guestChat(token);
        if (!mounted) return;
        _open(token);
        _chat?.chat = page.chat;
      } on GuestChatEndedException {
        await GuestStore.forget(widget.code);
        if (mounted) _open(null);
      } catch (_) {
        // can't tell now: try the chat (it says if it ended)
        if (mounted) _open(token);
      }
    } on BackendException catch (e) {
      if (mounted) setState(() => _cardError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _cardError = 'Check your connection and try again.');
      }
    }
  }

  /// The chat, open here: [token] its secret, or (null) not started yet:
  /// shown empty, and started by the first message.
  void _open(String? token) {
    _chat?.dispose();
    _token = token;
    _starting = null;
    final chat = GuestChatController(
      fetch: (after) async {
        final t = _token;
        if (t == null) {
          return GuestChatPage(
              chat: GuestChatSummary.notStarted(_card!), messages: const []);
        }
        return _api.guestChat(t, after: after);
      },
      post: (
              {String? body,
              String? gifId,
              int? replyToId,
              required String clientId}) async =>
          _api.guestSend(await _started(),
              body: body,
              gifId: gifId,
              replyToId: replyToId,
              clientId: clientId),
      react: (messageId, emoji) async =>
          _api.guestReact(await _started(), messageId, emoji),
      read: (upTo) async {
        final t = _token;
        if (t != null) await _api.guestRead(t, upTo);
      },
      gifs: (
              {required bool stickers,
              String query = '',
              int offset = 0}) async =>
          _api.guestGifs(await _started(),
              stickers: stickers, query: query, offset: offset),
      onEnded: () => unawaited(GuestStore.forget(widget.code)),
    );
    setState(() => _chat = chat);
    unawaited(chat.start());
  }

  /// The chat's secret: it starts now if it hasn't (by sending, the guest
  /// agrees: 18 or older, and the Community Guidelines). What stops it
  /// (e.g. too many chats) is said.
  Future<String> _started() {
    final token = _token;
    if (token != null) return Future.value(token);
    return _starting ??= () async {
      try {
        final started = await _api.start(widget.code);
        await GuestStore.saveToken(widget.code, started.token);
        _token = started.token;
        if (mounted) setState(() => _chat?.chat = started.chat);
        return started.token;
      } catch (e) {
        _starting = null; // the next message tries again
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              content: Text(e is BackendException
                  ? e.message
                  : 'Check your connection and try again.')));
        }
        rethrow;
      }
    }();
  }

  /// A new chat after one ended.
  void _again() => _open(null);

  Future<void> _end() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this chat?'),
        content: const Text(
            'It’s deleted for both of you, and you can’t get it back.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('End chat')),
        ],
      ),
    );
    final token = _token;
    if (sure != true || token == null) return;
    try {
      await _api.guestEnd(token);
    } catch (_) {}
    _chat?.markEnded();
  }

  /// "Join HUNTR to keep talking": what happens, then sign up.
  Future<void> _join() async {
    final card = _card;
    final chat = _chat?.chat;
    final token = _token;
    final go = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _JoinIntro(
            hostName: card?.name ?? chat?.name ?? '',
            hostAnimal: card?.avatar ?? chat?.avatar ?? 'fox',
            myName: chat?.myName,
            myAnimal: chat?.myAvatar,
            minutesLeft: chat?.minutesLeft(DateTime.now()))));
    if (go != true) return;
    if (token != null && !(_chat?.ended ?? true)) {
      await GuestStore.saveJoin(token);
    }
    widget.onLeave();
  }

  /// How it works: the rules, and the Community Guidelines.
  void _info(int minutes) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              key: const Key('guestInfoSheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('How it works',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                _Rules(minutes: minutes),
                const SizedBox(height: 6),
                Align(
                    alignment: Alignment.centerLeft, child: _GuidelinesLink()),
              ],
            ),
          ),
        ),
      );

  void _profile() {
    final card = _card;
    if (card == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _HostProfile(
            card: card,
            onJoin: () {
              Navigator.of(context).pop();
              _join();
            })));
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final chat = _chat;
    if (card == null || chat == null) {
      return Scaffold(
        body: Center(
          child: _cardError == null
              ? const CircularProgressIndicator()
              : _Unavailable(message: _cardError!, onHuntr: widget.onLeave),
        ),
      );
    }
    final view = ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final summary = chat.chat;
        final started = summary != null && summary.started;
        return GuestChatView(
          controller: chat,
          onOpenProfile: _profile,
          intro: GuestChatIntro(
            animal: started ? summary.myAvatar : card.avatar,
            title: started ? 'Hi, ${summary.myName}' : 'Say hi to ${card.name}',
            // the rest is behind (i) in the header
            text: started
                ? 'You’re anonymous to each other.'
                : 'You’re anonymous. No account needed.',
            actions: [
              FilledButton.icon(
                key: const Key('guestJoin'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: _join,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Join HUNTR to keep talking'),
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('guestInfo'),
              tooltip: 'How it works',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => _info(card.idleMinutes),
            ),
            if (!chat.ended && _token != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  key: const Key('guestEndChat'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8A80)),
                  onPressed: _end,
                  child: const Text('End'),
                ),
              ),
          ],
          ended: _EndedBar(onAgain: _again, onJoin: widget.onLeave),
        );
      },
    );
    // a computer: the host's card beside the chat
    if (MediaQuery.sizeOf(context).width < 1000) return view;
    return Scaffold(
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 380,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 28, 12, 28),
              children: [
                const _Brand(),
                const SizedBox(height: 24),
                _HostCard(card: card),
                const SizedBox(height: 16),
                _Rules(minutes: card.idleMinutes),
                const SizedBox(height: 16),
                _JoinButton(onPressed: _join),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: HuntrColors.border),
          Expanded(child: view),
        ]),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Text('HUNTR',
      style: TextStyle(
          color: HuntrColors.orange,
          fontSize: 20,
          letterSpacing: 1,
          fontWeight: FontWeight.w800));
}

/// The host as guests see them: their anonymous card only.
class _HostCard extends StatelessWidget {
  const _HostCard({required this.card});

  final GuestLinkCard card;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2A160B),
                Color(0xFF161210),
                Color(0xFF111114)
              ]),
          border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          SizedBox.square(
            dimension: 116,
            child: AnonymousArt(animal: card.avatar, radius: 58, size: 116),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HuntrColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('ANONYMOUS',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: HuntrColors.orange)),
          ),
          const SizedBox(height: 10),
          Text(card.name,
              key: const Key('guestHostName'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ]),
      );
}

class _Rules extends StatelessWidget {
  const _Rules({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: HuntrColors.orange),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Color(0xFFC9CAD1), height: 1.45))),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HuntrColors.border),
      ),
      child: Column(children: [
        line(
            Icons.timer_outlined,
            'The chat ends $minutes minutes after your last message. After '
            'that you can’t open it, and they can read it for 7 days.'),
        const SizedBox(height: 12),
        line(
            Icons.visibility_outlined,
            'They can read what you send. Don’t share anything you wouldn’t '
            'want kept.'),
        const SizedBox(height: 12),
        line(
            Icons.verified_user_outlined,
            'Only for people 18 or older. By sending a message, you agree to '
            'the Community Guidelines.'),
      ]),
    );
  }
}

class _GuidelinesLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final agreements = ServicesScope.agreementsOf(context);
    if (agreements == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              AgreementScreen.communityGuidelines(agreements: agreements))),
      icon: const Icon(Icons.shield_outlined, size: 18),
      label: const Text('Community Guidelines'),
    );
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        onPressed: onPressed,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Join HUNTR to keep talking'),
      );
}

/// The link's page before a chat: the host's card, what to know, agreeing
/// (18+, the rules), and Start anonymous chat.
/// The host's anonymous profile, as a guest sees it: the card only (no
/// Threads), and joining HUNTR.
class _HostProfile extends StatelessWidget {
  const _HostProfile({required this.card, required this.onJoin});

  final GuestLinkCard card;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Anonymous profile')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _HostCard(card: card),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Who they are stays private',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text(
                          'Their name, photos and profile aren’t shown here. '
                          'On HUNTR, you can both agree to swap profiles and '
                          'see who the other is.',
                          style:
                              TextStyle(color: Color(0xFFC9CAD1), height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _JoinButton(onPressed: onJoin),
              ],
            ),
          ),
        ),
      );
}

/// Before signing up: the chat comes along, both stay anonymous.
class _JoinIntro extends StatelessWidget {
  const _JoinIntro({
    required this.hostName,
    required this.hostAnimal,
    this.myName,
    this.myAnimal,
    this.minutesLeft,
  });

  final String hostName;
  final String hostAnimal;
  final String? myName;
  final String? myAnimal;
  final int? minutesLeft;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (myAnimal != null)
                    SizedBox.square(
                      dimension: 84,
                      child: AnonymousArt(
                          animal: myAnimal!,
                          radius: 42,
                          size: 84,
                          ring: HuntrColors.border),
                    ),
                  if (myAnimal != null) const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 84,
                    child:
                        AnonymousArt(animal: hostAnimal, radius: 42, size: 84),
                  ),
                ]),
                const SizedBox(height: 22),
                Text('Keep talking with $hostName',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                    myName == null
                        ? 'Sign up and chat with them on HUNTR. You both stay '
                            'anonymous.'
                        : 'Sign up and your chat moves to HUNTR. You stay '
                            '$myName, they stay anonymous, and your messages '
                            'come with you. The chat won’t expire anymore.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFFC9CAD1), fontSize: 15, height: 1.5)),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Icon(Icons.theater_comedy_outlined,
                          size: 18, color: HuntrColors.orange),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text(
                              'Neither of you sees the other’s profile unless '
                              'you both agree to swap.',
                              style: TextStyle(height: 1.45))),
                    ]),
                    if (minutesLeft != null) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(Icons.timer_outlined,
                            size: 18, color: HuntrColors.orange),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                'Your chat stays open while you sign up: '
                                '$minutesLeft min left.',
                                style: const TextStyle(height: 1.45))),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  key: const Key('guestJoinContinue'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                          fontFamily: huntrFontFamily,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800)),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Sign up or log in'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EndedBar extends StatelessWidget {
  const _EndedBar({required this.onAgain, required this.onJoin});

  final VoidCallback onAgain;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          key: const Key('guestChatEnded'),
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: HuntrColors.border),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('This chat has ended',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'There were no messages from you for a while. You can’t '
                'open it anymore.',
                style: TextStyle(color: HuntrColors.muted, height: 1.45)),
            const SizedBox(height: 14),
            // one above the other: each label on one line at any width
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: onJoin,
              child: const Text('Join HUNTR'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder()),
              onPressed: onAgain,
              child: const Text('Start a new chat'),
            ),
          ]),
        ),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onHuntr});

  final String message;
  final VoidCallback onHuntr;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.link_off_rounded,
              size: 48, color: HuntrColors.muted),
          const SizedBox(height: 14),
          Text(message,
              key: const Key('guestLinkUnavailable'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 18),
          FilledButton(onPressed: onHuntr, child: const Text('Go to HUNTR')),
        ]),
      );
}
