import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../state/block_state.dart';
import '../widgets/block_gate.dart';
import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../state/tap_state.dart';
import '../theme.dart';
import '../widgets/profile_tile.dart';
import '../widgets/avatar.dart';
import '../widgets/network_photo.dart';
import '../widgets/share_sheet.dart';
import 'chat_screen.dart';
import '../widgets/profile/gradient_button.dart';
import '../widgets/profile/status_pill.dart';
import '../widgets/profile/profile_meta.dart';
import '../widgets/profile/profile_section.dart';
import '../widgets/profile/looking_for_pill.dart';
import '../widgets/profile/photo_gallery.dart';
import '../flows/accept_with_album.dart';
import '../widgets/stories/profile_stories.dart';
import '../widgets/stories/reaction_burst.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required String this.profileId})
      : previewProfile = null,
        person = null,
        onMessage = null,
        showDistance = true;

  /// Someone's profile from outside Explore (e.g. a chat): they may not be in
  /// the nearby list. [onMessage] replaces opening a new chat (going back to
  /// the one it came from).
  ProfileScreen.person(
      {super.key, required Profile this.person, this.onMessage})
      : profileId = person.id,
        previewProfile = null,
        showDistance = true;

  /// Your own profile exactly as other people see it, without the actions
  /// that only make sense on someone else's profile.
  const ProfileScreen.preview(
      {super.key, required Profile profile, this.showDistance = true})
      : profileId = null,
        person = null,
        onMessage = null,
        previewProfile = profile;

  final String? profileId;
  final Profile? previewProfile;
  final Profile? person;
  final VoidCallback? onMessage;

  /// In a preview: whether others can see your distance.
  final bool showDistance;

  bool get _isPreview => previewProfile != null;

  @override
  Widget build(BuildContext context) {
    if (_isPreview) return _page(context);
    final p = person ?? AppScope.of(context).profileById(profileId!);
    // a block shows only that (checked again each time this opens); each
    // opening is one visit in their Viewers
    return _CountsAsVisit(
        userId: p?.backendId,
        child: BlockGate(userId: p?.backendId, child: Builder(builder: _page)));
  }

  Widget _page(BuildContext context) {
    final app = AppScope.of(context);
    final p = previewProfile ?? person ?? app.profileById(profileId!);
    if (p == null) {
      return const Scaffold(
          body: Center(child: Text('This profile is no longer available.')));
    }
    final text = Theme.of(context).textTheme;
    final fav = app.isFavorite(p.id);
    final height = MediaQuery.sizeOf(context).height;
    final conn = app.connectionWith(p.id);
    final request = app.requestWith(p.id);

    // Wide screens (web, tablets): photo card left, details right.
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final List<Widget> actions = _isPreview
        ? const []
        : [
            _CircleButton(
              child: IconButton(
                tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(
                    fav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: fav ? HuntrColors.orange : null),
                onPressed: () => app.toggleFavorite(p.id),
              ),
            ),
            _CircleButton(
              child: PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) => v == 'block'
                    ? _confirmBlock(context, p)
                    : _report(context, p),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'report',
                      child: ListTile(
                          leading: Icon(Icons.flag_outlined),
                          title: Text('Report'))),
                  PopupMenuItem(
                      value: 'block',
                      child: ListTile(
                          leading: Icon(Icons.block), title: Text('Block'))),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ];
    final Widget gallery = Stack(
      fit: StackFit.expand,
      children: [
        PhotoGallery(profile: p, firstIsAvatar: !_isPreview),
        const IgnorePointer(
            child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.25, 0.7, 1],
              colors: [
                Color(0x990F1014),
                Colors.transparent,
                Colors.transparent,
                HuntrColors.night
              ],
            ),
          ),
        )),
      ],
    );
    final Widget details = Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, wide ? 24 : 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(p.nameAndAge,
                    style: text.headlineLarge?.copyWith(
                        fontSize: 40,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              if (p.verified) ...[
                const SizedBox(width: 8),
                const Tooltip(
                    message: 'Verified',
                    child: Icon(Icons.verified, color: HuntrColors.orange)),
              ],
              if (p.isNew) ...[
                const SizedBox(width: 12),
                const NewBadge(),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ProfileMeta(
                icon: p.online ? null : Icons.schedule,
                leading: p.online ? const OnlineDot(size: 10) : null,
                label: p.activeLabel(DateTime.now()),
                color: p.online ? HuntrColors.online : HuntrColors.muted,
              ),
              ProfileMeta(
                  icon: Icons.near_me_outlined,
                  label: _isPreview
                      ? (showDistance
                          ? 'Distance shown to others'
                          : 'Distance hidden')
                      : p.distanceLabel),
              if (p.pronouns != null)
                ProfileMeta(icon: Icons.person_outline, label: p.pronouns!),
              if (p.heightCm != null)
                ProfileMeta(icon: Icons.height, label: '${p.heightCm} cm'),
            ],
          ),
          const SizedBox(height: 28),
          if (!_isPreview && conn == Connection.incoming)
            Container(
              margin: const EdgeInsets.only(bottom: 22),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HuntrColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: HuntrColors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                const Icon(Icons.mark_chat_unread_outlined,
                    color: HuntrColors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (request?.note == null
                            ? '${p.name} wants to chat with you.'
                            : '${p.name} wants to chat: "${request!.note}"') +
                        (p.albumById(request?.albumId) == null
                            ? ''
                            : '\nAccept to receive their "${p.albumById(request?.albumId)!.name}" album.'),
                  ),
                ),
              ]),
            ),
          // their stories (mine, with Add Story, on my own profile)
          ProfileStories(profile: p, mine: _isPreview),
          // About, Stats, Looking for (and interests), divided
          ..._divided([
            if (p.bio.isNotEmpty)
              ProfileSection(
                  title: 'About',
                  child: Text(p.bio,
                      style: const TextStyle(
                          fontSize: 17, height: 1.5, color: Colors.white))),
            // their stats, in the units I chose (unset ones aren't shown)
            if (p.stats.lines(app.myStats.units) case final lines
                when lines.isNotEmpty)
              ProfileSection(
                title: 'Stats',
                child: _StatsGrid(key: const Key('profileStats'), lines: lines),
              ),
            if (p.lookingFor.isNotEmpty)
              ProfileSection(
                title: 'Looking for',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // exactly what they picked, all alike
                    for (final choice in p.lookingFor)
                      LookingForPill(choice: choice),
                  ],
                ),
              ),
            if (p.interests.isNotEmpty)
              ProfileSection(
                title: 'Interests',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final i in p.interests) Chip(label: Text(i))],
                ),
              ),
          ]),
        ],
      ),
    );
    // ---- the next step for this connection, always in reach of the thumb ----
    final Widget bottomBar = SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: _isPreview
            ? const _PreviewNotice()
            : p.backendId != null
                // opened from my Unmatched list: only taking them off it
                ? p.unmatched
                    ? _RemoveUnmatchButton(profile: p)
                    : Row(children: [
                        if (TapScope.of(context) != null) ...[
                          _TapButton(profile: p),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                            child: _MessageButton(
                                profile: p, onMessage: onMessage)),
                      ])
                : switch (conn) {
                    Connection.none => GradientButton(
                        key: const Key('sendRequest'),
                        icon: Icons.send_rounded,
                        label: 'Send chat request',
                        onPressed: () => _requestSheet(context, p),
                      ),
                    Connection.outgoing => Row(children: [
                        const Expanded(
                          child: StatusPill(
                              icon: Icons.hourglass_top_rounded,
                              label: 'Request sent · waiting'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () => app.cancelRequest(p.id),
                            child: const Text('Cancel')),
                      ]),
                    Connection.incoming => Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 52),
                                shape: const StadiumBorder()),
                            onPressed: () {
                              app.declineRequest(p.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Request from ${p.name} declined')));
                            },
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: GradientButton(
                            key: const Key('acceptRequest'),
                            icon: Icons.check_rounded,
                            label: 'Accept',
                            onPressed: () => acceptWithAlbum(context, p),
                          ),
                        ),
                      ]),
                    Connection.connected => GradientButton(
                        icon: Icons.chat_bubble_rounded,
                        label: 'Message',
                        onPressed: () => _openChat(context, p),
                      ),
                  },
      ),
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      flex: 5,
                      child: _WideGallery(
                          profile: p,
                          firstIsAvatar: !_isPreview,
                          actions: actions),
                    ),
                    const SizedBox(width: 32),
                    Flexible(
                      flex: 6,
                      // the details scroll; the next step (Tap, Message)
                      // stays in view under them
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                              child: SingleChildScrollView(child: details)),
                          bottomBar,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: height * 0.52,
            pinned: true,
            stretch: true,
            backgroundColor: HuntrColors.night,
            automaticallyImplyLeading: false,
            leadingWidth: 72,
            leading: const _CircleButton(child: BackButton()),
            actions: actions,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: gallery,
            ),
          ),
          SliverToBoxAdapter(child: details),
        ],
      ),
      bottomNavigationBar: bottomBar,
    );
  }

  Future<void> _requestSheet(BuildContext context, Profile p) async {
    final choice = await showShareSheet(
      context,
      title: 'Chat request to ${p.name}',
      subtitle:
          'Pick an album to send. If ${p.name} approves, you both receive each other\'s chosen album and can start chatting.',
      actionLabel: 'Send request',
      actionIcon: Icons.send_rounded,
      withNote: true,
    );
    if (choice == null || !context.mounted) return;
    AppScope.read(context)
        .sendRequest(p, note: choice.note, albumId: choice.albumId);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Request sent to ${p.name}. We\'ll let you know when they reply.')));
  }

  void _openChat(BuildContext context, Profile p) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(profileId: p.id)));
  }

  Future<void> _confirmBlock(BuildContext context, Profile p) async {
    if (!await confirmBlock(context) || !context.mounted) return;
    final blocks = BlockScope.read(context);
    final id = p.backendId;
    if (blocks != null && id != null) {
      // a real person: the backend blocks it (this screen then shows only
      // the block); the chat stays, closed
      try {
        await blocks.block(id);
        if (!context.mounted) return;
        AppScope.read(context).block(p.id);
        unawaited(MessagingScope.read(context)?.refresh());
      } on BackendException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
      return;
    }
    AppScope.read(context).block(p.id);
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${p.name} is blocked')));
  }

  void _report(BuildContext context, Profile p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Report ${p.name}',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final reason in [
              'Fake profile',
              'Inappropriate photos',
              'Harassment',
              'Spam or scam',
              'Underage'
            ])
              ListTile(
                title: Text(reason),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Thanks. Our team will review this report.')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the action bar when previewing your own profile.
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profilePreviewNotice'),
      height: 58,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: HuntrColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: HuntrColors.orange, width: 1.4),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.visibility_outlined, size: 22, color: HuntrColors.orange),
        SizedBox(width: 10),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'Preview',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' · This is how others see your profile'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

/// A dark round backdrop so header buttons stay visible over any photo.
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: DecoratedBox(
        decoration: const BoxDecoration(
            color: Color(0xB3000000), shape: BoxShape.circle),
        child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white), child: child),
      ),
    );
  }
}

/// On a profile opened from my Unmatched Users list, instead of Message.
class _RemoveUnmatchButton extends StatefulWidget {
  const _RemoveUnmatchButton({required this.profile});

  final Profile profile;

  @override
  State<_RemoveUnmatchButton> createState() => _RemoveUnmatchButtonState();
}

class _RemoveUnmatchButtonState extends State<_RemoveUnmatchButton> {
  bool _removing = false;

  Future<void> _remove() async {
    final messaging = MessagingScope.read(context);
    if (_removing || messaging == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removing = true);
    try {
      await messaging.removeUnmatch(userId: widget.profile.backendId);
      messenger.showSnackBar(const SnackBar(
          content: Text('Welcome back! 💛 They’re off your Unmatched list.')));
      navigator.pop(true);
    } on BackendException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      key: const Key('removeUnmatchButton'),
      icon: Icons.person_add_alt_1_rounded,
      label: _removing ? 'Removing…' : 'Remove from Unmatch List',
      onPressed: _remove,
    );
  }
}

/// On a real person's profile, beside Message: one tap and they get it in
/// their Taps inbox (no chat starts until they reply). Always "Tap": each
/// one goes (counted up on their side) with a big wave; presses within
/// [_gap] of the last one are ignored, so a burst is one tap.
class _TapButton extends StatefulWidget {
  const _TapButton({required this.profile});

  final Profile profile;

  @override
  State<_TapButton> createState() => _TapButtonState();
}

class _TapButtonState extends State<_TapButton> {
  /// The backend allows one tap per person each 2 seconds too.
  static const _gap = Duration(seconds: 2);

  bool _sending = false;

  /// Running for [_gap] after each tap: presses meanwhile are ignored.
  Timer? _cooling;

  @override
  void dispose() {
    _cooling?.cancel();
    super.dispose();
  }

  Future<void> _tap() async {
    final taps = TapScope.read(context);
    final userId = widget.profile.backendId;
    // a burst of presses: only the first
    if (_sending || taps == null || userId == null) return;
    if (_cooling?.isActive ?? false) return;
    _cooling = Timer(_gap, () {});
    final messenger = ScaffoldMessenger.of(context);
    final app = AppScope.read(context);
    setState(() => _sending = true);
    String message;
    try {
      await taps.send(userId);
      // a big wave: it went
      if (mounted) ReactionBurst.show(context, '👋', wave: true);
      message = 'Tap sent 👋 ${widget.profile.name} will see it in their Taps.';
    } on SessionRejectedException {
      return app.endSession();
    } on BackendException catch (e) {
      message = e.message;
    } catch (_) {
      message = "Your tap didn't go through. Check your connection and try "
          'again.';
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    messenger
      ..hideCurrentSnackBar()
      // gone by the time the next tap is allowed (it sits over the button)
      ..showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1800)));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('tapButton'),
      style: OutlinedButton.styleFrom(
        foregroundColor: HuntrColors.orange,
        side: const BorderSide(color: HuntrColors.orange),
        minimumSize: const Size(0, 52),
        shape: const StadiumBorder(),
      ),
      icon: _sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.waving_hand_rounded),
      label: const Text('Tap'),
      onPressed: _tap,
    );
  }
}

/// On a real person's profile: our direct conversation, or (no conversation
/// yet) my anonymous one with them - the backend decides; it's started the
/// first time.
class _MessageButton extends StatefulWidget {
  const _MessageButton({required this.profile, this.onMessage});

  final Profile profile;
  final VoidCallback? onMessage;

  @override
  State<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends State<_MessageButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (widget.onMessage != null) return widget.onMessage!();
    final messaging = MessagingScope.read(context);
    if (_opening || messaging == null) return;
    setState(() => _opening = true);
    int? id;
    String? error;
    try {
      id = await messaging.messageTarget(widget.profile);
    } on BackendException catch (e) {
      error = e.message;
    } catch (_) {
      error = "Couldn't open the chat. Check your connection and try again.";
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (id != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatScreen.conversation(
              conversationId: id!, other: widget.profile)));
    } else if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      key: const Key('messageButton'),
      icon: Icons.chat_bubble_rounded,
      label: _opening ? 'Opening chat…' : 'Message',
      onPressed: _open,
    );
  }
}

/// Opening someone's profile is one visit in their Viewers: recorded once
/// for as long as this screen is open (rebuilds don't add any), with an id
/// that makes a repeated request count once too. Not my own profile.
class _CountsAsVisit extends StatefulWidget {
  const _CountsAsVisit({required this.userId, required this.child});

  final int? userId;
  final Widget child;

  @override
  State<_CountsAsVisit> createState() => _CountsAsVisitState();
}

class _CountsAsVisitState extends State<_CountsAsVisit> {
  static final _random = Random.secure();

  /// This opening.
  final String _visitId = List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = widget.userId;
      if (!mounted || userId == null) return;
      if (userId == AppScope.read(context).myUserId) return;
      TapScope.read(context)?.recordView(userId, _visitId);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// [sections] with a thin line between each.
List<Widget> _divided(List<Widget> sections) => [
      for (final (i, section) in sections.indexed) ...[
        if (i > 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 22),
            child: Divider(height: 1, color: HuntrColors.border),
          ),
        section,
      ],
    ];

/// Stats as a grid: an icon in a circle, the label over the value; two
/// across where there's room.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({super.key, required this.lines});

  final List<(String, String)> lines;

  static const _icons = {
    'Height': Icons.height_rounded,
    'Weight': Icons.monitor_weight_outlined,
    'Body Type': Icons.accessibility_new_rounded,
    'Position': Icons.swap_vert_rounded,
    'Ethnicity': Icons.public_rounded,
    'Relationship Status': Icons.favorite_border_rounded,
    'Tribes': Icons.groups_outlined,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const gap = 16.0;
        final across = box.maxWidth >= 360 ? 2 : 1;
        final width = (box.maxWidth - gap * (across - 1)) / across;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final (label, value) in lines)
              SizedBox(
                width: width,
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HuntrColors.surface,
                      border: Border.all(color: HuntrColors.border),
                    ),
                    child: Icon(_icons[label] ?? Icons.info_outline_rounded,
                        size: 20, color: Colors.white70),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  color: HuntrColors.muted, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(value,
                              key: Key('profileStat-$label'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                ]),
              ),
          ],
        );
      });
}

/// Wide screens: the photo (back, favourite and more on it), and under it
/// their photos as thumbnails - the one shown outlined; tap one to see it.
class _WideGallery extends StatefulWidget {
  const _WideGallery(
      {required this.profile,
      required this.firstIsAvatar,
      required this.actions});

  final Profile profile;
  final bool firstIsAvatar;
  final List<Widget> actions;

  @override
  State<_WideGallery> createState() => _WideGalleryState();
}

class _WideGalleryState extends State<_WideGallery> {
  final _pages = PageController();
  int _page = 0;

  /// Thumbnails shown; past that, a "+N" tile.
  static const _thumbs = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int page) => _pages.animateToPage(page,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final urls = widget.profile.photoUrls;
    // five fit; more: four and "+N"
    final shown = urls.length <= _thumbs + 1 ? urls.length : _thumbs;
    final rest = urls.length - shown;
    final strip = urls.length > 1;
    // the photo (4:5) and the strip under it fit the space: as wide as there
    // is room for, but never taller than the window allows
    return LayoutBuilder(builder: (context, box) {
      const gap = 12.0, between = 10.0, tiles = _thumbs + 1.0, tile = 0.82;
      // the strip's height for a photo this tall (its tiles share the width)
      final perPhotoHeight = 0.8 / (tiles * tile);
      final fixed = gap - between * (tiles - 1) / (tiles * tile);
      var photoHeight = box.maxWidth * 5 / 4;
      if (box.maxHeight.isFinite) {
        final fits = strip
            ? (box.maxHeight - fixed) / (1 + perPhotoHeight)
            : box.maxHeight;
        if (fits < photoHeight) photoHeight = fits;
      }
      final photoWidth = photoHeight * 4 / 5;
      return SizedBox(
        width: photoWidth,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: photoHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(fit: StackFit.expand, children: [
                PhotoGallery(
                    profile: widget.profile,
                    firstIsAvatar: widget.firstIsAvatar,
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _page = i)),
                // only a top shade, for the buttons
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.22],
                        colors: [Color(0x990F1014), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                    top: 4, left: 4, child: _CircleButton(child: BackButton())),
                Positioned(
                  top: 4,
                  right: 0,
                  child: Row(
                      mainAxisSize: MainAxisSize.min, children: widget.actions),
                ),
              ]),
            ),
          ),
          if (strip) ...[
            const SizedBox(height: gap),
            Row(children: [
              for (var i = 0; i < _thumbs + 1; i++) ...[
                if (i > 0) const SizedBox(width: between),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: tile,
                    child: i < shown
                        ? _Thumb(
                            key: Key('profileThumb-$i'),
                            url: urls[i],
                            selected: i == _page,
                            onTap: () => _show(i))
                        : i == shown && rest > 0
                            ? _MoreThumb(rest: rest, onTap: () => _show(shown))
                            : const SizedBox(),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      );
    });
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(
      {super.key,
      required this.url,
      required this.selected,
      required this.onTap});

  final String url;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? HuntrColors.orange : HuntrColors.border,
                width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: NetworkPhoto(url),
          ),
        ),
      );
}

/// "+4": more photos than thumbnails.
class _MoreThumb extends StatelessWidget {
  const _MoreThumb({required this.rest, required this.onTap});

  final int rest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const Key('profileThumbMore'),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: Text('+$rest',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
        ),
      );
}
