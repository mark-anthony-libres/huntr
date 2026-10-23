import 'dart:async';

import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../state/tap_state.dart';
import '../flows/open_person_profile.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/load_more_row.dart';
import '../widgets/pill_tabs.dart';
import '../widgets/me/section_states.dart';
import '../widgets/taps/tap_answers.dart';
import 'chat_screen.dart';
import 'chats_screen.dart' show timeLabel;
import 'profile_screen.dart';

/// The Taps tab: the taps waiting for me, newest first (opening one marks
/// it read; responding starts our chat), and beside them, Viewers: who
/// viewed my profile in the last 24 hours.
class TapsScreen extends StatefulWidget {
  const TapsScreen({super.key});

  @override
  State<TapsScreen> createState() => _TapsScreenState();
}

class _TapsScreenState extends State<TapsScreen> {
  bool _viewersTab = false;

  void _show({required bool viewers}) {
    setState(() => _viewersTab = viewers);
    // fresh each time it's opened
    if (viewers) TapScope.read(context)?.refreshViewers();
  }

  @override
  Widget build(BuildContext context) {
    final taps = TapScope.of(context);
    final text = Theme.of(context).textTheme;
    final list = taps?.taps;
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: HuntrColors.orange,
          onRefresh: () =>
              (_viewersTab ? taps?.refreshViewers() : taps?.refresh()) ??
              Future.value(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: ShaderMask(
                  shaderCallback: HuntrColors.accentGradient.createShader,
                  child: Text('Taps',
                      style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              // ---- Taps / Viewers ----
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: PillTabs(
                  selected: _viewersTab ? 1 : 0,
                  onChanged: (i) => _show(viewers: i == 1),
                  tabs: [
                    PillTab(
                        key: const Key('tapsTab'),
                        icon: Icons.waving_hand_outlined,
                        label: 'Taps',
                        badge: taps?.unreadCount ?? 0),
                    const PillTab(
                        key: Key('viewersTab'),
                        icon: Icons.visibility_outlined,
                        label: 'Viewers'),
                  ],
                ),
              ),
              if (_viewersTab)
                ..._ViewersList.rows(context, taps, now)
              else ...[
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 16),
                  child: Text(
                      'People who tapped you. Say hi back to start a chat.',
                      style: TextStyle(color: HuntrColors.muted, height: 1.4)),
                ),
                // no backend (sample data): nothing to load, so empty
                if (taps != null && list == null && taps.error == null)
                  const LoadingRows(count: 3, height: 76)
                else if (taps != null && list == null)
                  LoadFailedCard(
                    title: "Couldn't load your taps",
                    message: taps.error!,
                    onRetry: taps.refresh,
                    retryKey: const Key('tapsRetry'),
                  )
                else if (list == null || list.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.waving_hand_outlined,
                    title: 'No taps yet',
                    message: "When someone taps you, they'll show up here. "
                        'Say hi back to start a chat.',
                  )
                else
                  for (final tap in list)
                    _TapRow(
                      tap: tap,
                      time: timeLabel(tap.receivedAt, now),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TapDetailScreen(tap: tap))),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({required this.tap, required this.time, required this.onTap});

  final ReceivedTap tap;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !tap.isRead;
    final first = tap.answers.where((a) => a.answer != null).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('tap-${tap.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: unread
                      ? HuntrColors.orange.withValues(alpha: 0.6)
                      : HuntrColors.border),
            ),
            child: Row(children: [
              Avatar(profile: tap.sender, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${tap.sender.name} tapped you 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w600),
                        ),
                      ),
                      Text(time,
                          style: const TextStyle(
                              color: HuntrColors.muted, fontSize: 13)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      first?.answer ?? 'Say hi back 👋',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: unread ? Colors.white : HuntrColors.muted),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 10),
                Container(
                  key: Key('tapUnread-${tap.id}'),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: HuntrColors.orange),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// One tap: who it's from (and any answers, on taps sent while Tap had
/// questions), and my response (which starts our chat, with the tap shown
/// first). Opening it marks it read.
class TapDetailScreen extends StatefulWidget {
  const TapDetailScreen({super.key, required this.tap});

  final ReceivedTap tap;

  @override
  State<TapDetailScreen> createState() => _TapDetailScreenState();
}

class _TapDetailScreenState extends State<TapDetailScreen> {
  final _reply = TextEditingController();
  bool _sending = false;
  String? _error;

  /// Kept across retries, so a response is never saved twice.
  String? _clientId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(TapScope.read(context)?.markRead(widget.tap));
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _respond() async {
    final body = _reply.text.trim();
    if (body.isEmpty) {
      return setState(() => _error = 'Write something to send.');
    }
    final taps = TapScope.read(context);
    final messaging = MessagingScope.read(context);
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    if (taps == null) return;
    _clientId ??= messaging?.newClientId() ??
        DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response =
          await taps.respond(widget.tap, body: body, clientId: _clientId!);
      unawaited(messaging?.refresh());
      await navigator.pushReplacement(MaterialPageRoute(
          builder: (_) => ChatScreen.conversation(
              conversationId: response.conversationId,
              other: widget.tap.sender)));
    } on SessionRejectedException {
      navigator.pop();
      app.endSession();
    } catch (error) {
      // e.g. it isn't available anymore: the inbox shows what's left
      if (error is BackendException) unawaited(taps.refresh());
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error is BackendException
            ? error.message
            : "Your reply didn't go through. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tap = widget.tap;
    final sender = tap.sender;
    return Scaffold(
      appBar: AppBar(title: const Text('Tap')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                InkWell(
                  key: const Key('tapSender'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProfileScreen.person(person: sender))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Avatar(profile: sender, size: 60),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${sender.name} tapped you 👋',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            const Text('Tap to see their profile',
                                style: TextStyle(color: HuntrColors.muted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: HuntrColors.muted),
                    ]),
                  ),
                ),
                if (tap.answers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: HuntrColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: HuntrColors.border),
                    ),
                    child: TapAnswers(answers: tap.answers),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'They want to get to know you 💛 Say hi back to start '
                  'chatting.',
                  style: TextStyle(color: HuntrColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(_error!,
                  key: const Key('tapReplyError'),
                  style: const TextStyle(color: HuntrColors.coral)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('tapReply'),
                  controller: _reply,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Say hi back…'),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const Key('tapRespond'),
                tooltip: 'Respond',
                style: IconButton.styleFrom(
                    backgroundColor: HuntrColors.orange,
                    foregroundColor: Colors.black),
                onPressed: _sending ? null : _respond,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---- Viewers ----

/// "Just now", "10 minutes ago", "1 hour ago".
String visitedAgo(DateTime at, DateTime now) {
  final gone = now.difference(at);
  if (gone.inMinutes < 1) return 'Just now';
  if (gone.inHours < 1) {
    return gone.inMinutes == 1
        ? '1 minute ago'
        : '${gone.inMinutes} minutes ago';
  }
  return gone.inHours == 1 ? '1 hour ago' : '${gone.inHours} hours ago';
}

/// The Viewers tab's content: who viewed my profile in the last 24 hours,
/// latest first, each with how many times.
abstract final class _ViewersList {
  static List<Widget> rows(BuildContext context, TapState? taps, DateTime now) {
    final viewers = taps?.viewers;
    return [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 16),
        child: Text('People who viewed your profile in the last 24 hours.',
            style: TextStyle(color: HuntrColors.muted, height: 1.4)),
      ),
      if (taps != null && viewers == null && taps.viewersError == null)
        const LoadingRows(count: 3, height: 76)
      else if (taps != null && viewers == null)
        LoadFailedCard(
          title: "Couldn't load your viewers",
          message: taps.viewersError!,
          onRetry: taps.refreshViewers,
          retryKey: const Key('viewersRetry'),
        )
      else if (viewers == null || viewers.isEmpty)
        const EmptyStateCard(
          icon: Icons.visibility_outlined,
          title: 'No viewers yet',
          message: "When someone views your profile, they'll show up here "
              'for 24 hours, with how many times they looked.',
        )
      else ...[
        for (final viewer in viewers)
          _ViewerRow(
            viewer: viewer,
            time: visitedAgo(viewer.lastViewedAt, now),
            onTap: () => openPersonProfile(context, viewer.person),
          ),
        if (taps != null && taps.moreViewers)
          LoadMoreRow(
            key: ValueKey('viewers-more-${viewers.length}'),
            onVisible: () => taps.refreshViewers(more: true),
          ),
      ],
    ];
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow(
      {required this.viewer, required this.time, required this.onTap});

  final ProfileViewer viewer;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final person = viewer.person;
    final visits = viewer.visits == 1 ? '1 visit' : '${viewer.visits} visits';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('viewer-${person.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: HuntrColors.border),
            ),
            child: Row(children: [
              Avatar(profile: person, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          person.nameAndAge.isEmpty
                              ? person.shortName
                              : person.nameAndAge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(time,
                          style: const TextStyle(
                              color: HuntrColors.muted, fontSize: 13)),
                    ]),
              ),
              const SizedBox(width: 8),
              // how many times, in the accent
              Container(
                key: Key('viewerVisits-${person.id}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: HuntrColors.orange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: HuntrColors.orange.withValues(alpha: 0.5)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.visibility_rounded,
                      size: 15, color: HuntrColors.orange),
                  const SizedBox(width: 5),
                  Text(visits,
                      style: const TextStyle(
                          color: HuntrColors.orange,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
