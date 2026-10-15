import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final me = Profile(
      id: 'me',
      name: app.myName.isEmpty ? 'You' : app.myName,
      age: app.myAge,
      distanceKm: 0,
      bio: app.myBio,
      interests: const [],
      lookingFor: app.myLookingFor,
      online: app.showOnline,
      lastActive: DateTime.now(),
      hue: 28,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            ShaderMask(
              shaderCallback: HuntrColors.accentGradient.createShader,
              child: Text('Me', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: HuntrColors.surface, borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(gradient: HuntrColors.accentGradient, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(me.initials,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${me.name}, ${me.age}', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      app.myBio.isEmpty ? 'Add a short bio so people know what to say' : app.myBio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: HuntrColors.muted),
                    ),
                  ]),
                ),
                IconButton(
                  tooltip: 'Edit profile',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(context, app),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in app.myLookingFor)
                Chip(avatar: Icon(l.icon, size: 18, color: HuntrColors.amber), label: Text(l.label)),
            ]),
            const SizedBox(height: 24),
            Text('PRIVACY', style: text.labelMedium?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show my distance'),
              subtitle: const Text('Others see roughly how far away you are'),
              value: app.showDistance,
              onChanged: (v) => app.updateMe(distance: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show when I\'m online'),
              subtitle: const Text('Turn off to browse without the green dot'),
              value: app.showOnline,
              onChanged: (v) => app.updateMe(online: v),
            ),
            const SizedBox(height: 12),
            Text('SAFETY', style: text.labelMedium?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.shield_outlined),
              title: Text('Safety tips'),
              subtitle: Text('Meet in public places and tell a friend where you are going'),
            ),
          ],
        ),
      ),
    );
  }

  void _edit(BuildContext context, AppState app) {
    final name = TextEditingController(text: app.myName);
    final bio = TextEditingController(text: app.myBio);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Edit profile', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
            controller: bio,
            maxLines: 3,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Bio', hintText: 'What should people know about you?'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              app.updateMe(name: name.text, bio: bio.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
