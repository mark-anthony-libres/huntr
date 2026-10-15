import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profileById(profileId);
    if (p == null) return const Scaffold(body: Center(child: Text('This profile is no longer available.')));
    final text = Theme.of(context).textTheme;
    final fav = app.isFavorite(p.id);
    final height = MediaQuery.sizeOf(context).height;

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
                icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: fav ? HuntrColors.amber : null),
                onPressed: () => app.toggleFavorite(p.id),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) => v == 'block' ? _confirmBlock(context, p) : _report(context, p),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Report'))),
                  PopupMenuItem(value: 'block', child: ListTile(leading: Icon(Icons.block), title: Text('Block'))),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(tag: 'art-${p.id}', child: ProfileArt(profile: p, fontSize: 110)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.25, 0.7, 1],
                        colors: [Color(0x990F1014), Colors.transparent, Colors.transparent, HuntrColors.night],
                      ),
                    ),
                  ),
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
                            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (p.verified) ...[
                        const SizedBox(width: 8),
                        const Tooltip(message: 'Verified', child: Icon(Icons.verified, color: HuntrColors.amber)),
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
                        color: p.online ? HuntrColors.online : HuntrColors.muted,
                      ),
                      _Meta(icon: Icons.near_me_outlined, label: p.distanceLabel),
                      if (p.pronouns != null) _Meta(icon: Icons.person_outline, label: p.pronouns!),
                      if (p.heightCm != null) _Meta(icon: Icons.height, label: '${p.heightCm} cm'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Section(title: 'About', child: Text(p.bio, style: text.bodyLarge?.copyWith(height: 1.45))),
                  _Section(
                    title: 'Looking for',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in p.lookingFor)
                          Chip(avatar: Icon(l.icon, size: 18, color: HuntrColors.amber), label: Text(l.label)),
                      ],
                    ),
                  ),
                  _Section(
                    title: 'Interests',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final i in p.interests) Chip(label: Text(i))],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // ---- one-tap actions, always in reach of the thumb ----
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52), shape: const StadiumBorder()),
                  icon: const Text('👋', style: TextStyle(fontSize: 18)),
                  label: const Text('Say hi'),
                  onPressed: () {
                    app.wave(p);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text('You waved at ${p.name}'),
                        action: SnackBarAction(label: 'Open chat', onPressed: () => _openChat(context, p)),
                      ));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DecoratedBox(
                  decoration: const BoxDecoration(gradient: HuntrColors.accentGradient, borderRadius: BorderRadius.all(Radius.circular(30))),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.black),
                    icon: const Icon(Icons.chat_bubble_rounded),
                    label: const Text('Message'),
                    onPressed: () => _openChat(context, p),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChat(BuildContext context, Profile p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(profileId: p.id)));
  }

  Future<void> _confirmBlock(BuildContext context, Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${p.name}?'),
        content: const Text('They won\'t be able to see you or message you, and your chat with them is deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    AppScope.read(context).block(p.id);
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${p.name} is blocked')));
  }

  void _report(BuildContext context, Profile p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Report ${p.name}', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final reason in ['Fake profile', 'Inappropriate photos', 'Harassment', 'Spam or scam', 'Underage'])
              ListTile(
                title: Text(reason),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Thanks. Our team will review this report.')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({this.icon, this.leading, required this.label, this.color = HuntrColors.muted});
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
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}
