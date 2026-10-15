import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.profileId});
  final String profileId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AppState? _appRef;
  AppState get _app => _appRef!;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appRef != null) return; // runs again on every app-state change; set up only once
    _appRef = AppScope.read(context);
    _app.setOpenChat(widget.profileId);
  }

  @override
  void dispose() {
    _app.setOpenChat(null);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(Profile p, String text) {
    if (text.trim().isEmpty) return;
    _app.send(p, text);
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profileById(widget.profileId);
    if (p == null) return const Scaffold(body: Center(child: Text('This chat is no longer available.')));
    final c = app.conversationWith(p);
    final now = DateTime.now();
    final msgs = c.messages.reversed.toList();
    if (c.unread > 0) WidgetsBinding.instance.addPostFrameCallback((_) => app.markRead(p));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(profileId: p.id))),
          child: Row(children: [
            Avatar(profile: p, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  c.typing ? 'typing…' : '${p.activeLabel(now)} · ${p.distanceLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.typing || p.online ? HuntrColors.online : HuntrColors.muted,
                  ),
                ),
              ]),
            ),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: 'View profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(profileId: p.id))),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.isEmpty && !c.typing
                ? _ChatIntro(profile: p)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: msgs.length + (c.typing ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (c.typing && i == 0) return const _TypingBubble();
                      final idx = c.typing ? i - 1 : i;
                      final m = msgs[idx];
                      final older = idx + 1 < msgs.length ? msgs[idx + 1] : null;
                      final newer = idx > 0 ? msgs[idx - 1] : null;
                      final showTime = older == null || m.sentAt.difference(older.sentAt).inMinutes.abs() > 30;
                      final groupedWithNewer = newer != null && newer.fromMe == m.fromMe;
                      return Column(children: [
                        if (showTime) _TimeDivider(time: m.sentAt, now: now),
                        _Bubble(message: m, tail: !groupedWithNewer, showStatus: m.fromMe && newer == null),
                      ]);
                    },
                  ),
          ),

          // ---- quick replies keep the first message low-effort ----
          if (_input.text.isEmpty)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: quickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(quickReplies[i]),
                  onPressed: () => _send(p, quickReplies[i]),
                ),
              ),
            ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('messageInput'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: 'Message ${p.name}…'),
                    onSubmitted: (v) => _send(p, v),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedScale(
                  scale: _input.text.trim().isEmpty ? 0.85 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: IconButton.filled(
                    key: const Key('sendButton'),
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      backgroundColor: HuntrColors.amber,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    onPressed: _input.text.trim().isEmpty ? null : () => _send(p, _input.text),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatIntro extends StatelessWidget {
  const _ChatIntro({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Avatar(profile: profile, size: 88),
          const SizedBox(height: 14),
          Text('Say hi to ${profile.name}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'You both like ${profile.interests.take(2).join(' and ').toLowerCase()}. Start there!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.tail, required this.showStatus});
  final Message message;
  final bool tail;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    final r = const Radius.circular(20);
    final small = const Radius.circular(6);
    final isEmojiOnly = message.text.runes.length <= 2 && !RegExp(r'[A-Za-z0-9]').hasMatch(message.text);
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 2, bottom: tail ? 6 : 1),
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74),
            padding: isEmojiOnly ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: isEmojiOnly
                ? null
                : BoxDecoration(
                    gradient: me ? HuntrColors.accentGradient : null,
                    color: me ? null : HuntrColors.surfaceHigh,
                    borderRadius: BorderRadius.only(
                      topLeft: r,
                      topRight: r,
                      bottomLeft: me || !tail ? r : small,
                      bottomRight: me && tail ? small : r,
                    ),
                  ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: isEmojiOnly ? 40 : 15.5,
                height: 1.3,
                color: me ? Colors.black : Colors.white,
                fontWeight: me ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          if (showStatus)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: Text(
                message.status == MessageStatus.read ? 'Read' : 'Sent',
                style: const TextStyle(fontSize: 11, color: HuntrColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.time, required this.now});
  final DateTime time;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final clock = '$h:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(sameDay ? 'Today $clock' : '${time.day}/${time.month} $clock',
          style: const TextStyle(fontSize: 12, color: HuntrColors.muted)),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = ((_c.value * 3 - i) % 3).clamp(0.0, 1.0);
              final lift = (t < 0.5 ? t : 1 - t) * 2;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 7,
                height: 7,
                transform: Matrix4.translationValues(0, -4 * lift, 0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4 + 0.5 * lift),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
