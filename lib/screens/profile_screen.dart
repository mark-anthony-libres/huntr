import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/photo.dart';
import '../widgets/share_sheet.dart';
import 'chat_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profileById(profileId);
    if (p == null) {
      return const Scaffold(
          body: Center(child: Text('This profile is no longer available.')));
    }
    final text = Theme.of(context).textTheme;
    final fav = app.isFavorite(p.id);
    final height = MediaQuery.sizeOf(context).height;
    final conn = app.connectionWith(p.id);
    final request = app.requestWith(p.id);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: height * 0.52,
            pinned: true,
            stretch: true,
            backgroundColor: HuntrColors.night,
            actions: [
              IconButton(
                tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(
                    fav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: fav ? HuntrColors.amber : null),
                onPressed: () => app.toggleFavorite(p.id),
              ),
              PopupMenuButton<String>(
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
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _PhotoGallery(profile: p),
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
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('${p.name}, ${p.age}',
                            style: text.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (p.verified) ...[
                        const SizedBox(width: 8),
                        const Tooltip(
                            message: 'Verified',
                            child:
                                Icon(Icons.verified, color: HuntrColors.amber)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Meta(
                        icon: p.online ? null : Icons.schedule,
                        leading: p.online ? const OnlineDot(size: 10) : null,
                        label: p.activeLabel(DateTime.now()),
                        color:
                            p.online ? HuntrColors.online : HuntrColors.muted,
                      ),
                      _Meta(
                          icon: Icons.near_me_outlined, label: p.distanceLabel),
                      if (p.pronouns != null)
                        _Meta(icon: Icons.person_outline, label: p.pronouns!),
                      if (p.heightCm != null)
                        _Meta(icon: Icons.height, label: '${p.heightCm} cm'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (conn == Connection.incoming)
                    Container(
                      margin: const EdgeInsets.only(bottom: 22),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: HuntrColors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: HuntrColors.amber.withValues(alpha: 0.5)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.mark_chat_unread_outlined,
                            color: HuntrColors.amber),
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
                  _Section(
                      title: 'About',
                      child: Text(p.bio,
                          style: text.bodyLarge?.copyWith(height: 1.45))),
                  _Section(
                    title: 'Looking for',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in p.lookingFor)
                          Chip(
                              avatar: Icon(l.icon,
                                  size: 18, color: HuntrColors.amber),
                              label: Text(l.label)),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'Interests',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final i in p.interests) Chip(label: Text(i))
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // ---- the next step for this connection, always in reach of the thumb ----
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: switch (conn) {
            Connection.none => _GradientButton(
                key: const Key('sendRequest'),
                icon: Icons.send_rounded,
                label: 'Send chat request',
                onPressed: () => _requestSheet(context, p),
              ),
            Connection.outgoing => Row(children: [
                const Expanded(
                  child: _StatusPill(
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Request from ${p.name} declined')));
                    },
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _GradientButton(
                    key: const Key('acceptRequest'),
                    icon: Icons.check_rounded,
                    label: 'Accept',
                    onPressed: () => acceptWithAlbum(context, p),
                  ),
                ),
              ]),
            Connection.connected => _GradientButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Message',
                onPressed: () => _openChat(context, p),
              ),
          },
        ),
      ),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${p.name}?'),
        content: const Text(
            'They won\'t be able to see you or message you, and your chat with them is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
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

class _GradientButton extends StatelessWidget {
  const _GradientButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
          gradient: HuntrColors.accentGradient,
          borderRadius: BorderRadius.all(Radius.circular(30))),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52)),
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: HuntrColors.amber),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(
      {this.icon,
      this.leading,
      required this.label,
      this.color = HuntrColors.muted});
  final IconData? icon;
  final Widget? leading;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      leading ?? Icon(icon, size: 16, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color)),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

/// Approve [p]'s request after picking which of my albums to send back. Shared with the Chats screen.
Future<void> acceptWithAlbum(BuildContext context, Profile p) async {
  final choice = await showShareSheet(
    context,
    title: 'Accept ${p.name}\'s request',
    subtitle:
        'Pick an album to send to ${p.name}. Their chosen album is sent to you, and the chat opens.',
    actionLabel: 'Accept & share',
    actionIcon: Icons.check_rounded,
  );
  if (choice == null || !context.mounted) return;
  AppScope.read(context).acceptRequest(p, albumId: choice.albumId);
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ChatScreen(profileId: p.id)));
}

/// Swipeable public profile pictures with a page indicator.
class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({required this.profile});
  final Profile profile;

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  int _page = 0;
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta, int count) {
    final next = (_page + delta).clamp(0, count - 1);
    if (next != _page) {
      _pages.animateToPage(next,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final count = p.photos.isEmpty ? 1 : p.photos.length;
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        controller: _pages,
        itemCount: count,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => i == 0
            ? Hero(
                tag: 'art-${p.id}',
                child: ProfileArt(profile: p, fontSize: 110))
            : PhotoArt(photo: p.photos[i], radius: 0, iconSize: 96),
      ),
      // tap the left or right side to move between photos
      if (count > 1)
        Positioned.fill(
          child: Row(children: [
            Expanded(
                child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _go(-1, count))),
            Expanded(
                child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _go(1, count))),
          ]),
        ),
      if (count > 1)
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 6,
          child: IgnorePointer(
            child: Row(children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: i == _page ? 0.95 : 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}
