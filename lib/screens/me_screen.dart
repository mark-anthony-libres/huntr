import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/photo.dart';
import 'album_screen.dart';

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
              child: Text('Me',
                  style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: HuntrColors.surface,
                  borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                      gradient: HuntrColors.accentGradient,
                      shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(me.initials,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.black)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${me.name}, ${me.age}',
                            style: text.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          app.myBio.isEmpty
                              ? 'Add a short bio so people know what to say'
                              : app.myBio,
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
                Chip(
                    avatar: Icon(l.icon, size: 18, color: HuntrColors.amber),
                    label: Text(l.label)),
            ]),
            const SizedBox(height: 24),
            Text('MY ALBUM · ${app.myAlbum.length}',
                style: text.labelMedium
                    ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            const Text(
              'Private. Shared automatically with someone when you accept their chat request.',
              style: TextStyle(color: HuntrColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final ph in app.myAlbum)
                  Stack(fit: StackFit.expand, children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AlbumScreen(
                              title: 'My album', photos: app.myAlbum))),
                      child: PhotoArt(photo: ph, iconSize: 24),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => app.removeMyPhoto(ph.id),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 14, semanticLabel: 'Remove photo'),
                        ),
                      ),
                    ),
                  ]),
                InkWell(
                  key: const Key('addPhoto'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _addPhoto(context, app),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: HuntrColors.amber.withValues(alpha: 0.6),
                          width: 1.5),
                    ),
                    child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: HuntrColors.amber),
                          SizedBox(height: 2),
                          Text('Add',
                              style: TextStyle(
                                  fontSize: 12, color: HuntrColors.amber)),
                        ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('PRIVACY',
                style: text.labelMedium
                    ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
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
            Text('SAFETY',
                style: text.labelMedium
                    ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.shield_outlined),
              title: Text('Safety tips'),
              subtitle: Text(
                  'Meet in public places and tell a friend where you are going'),
            ),
          ],
        ),
      ),
    );
  }

  /// Until camera/gallery upload is wired up, "adding" a photo picks a sample subject.
  void _addPhoto(BuildContext context, AppState app) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add a photo', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                    'Sample photos for now. Camera and gallery upload come with the backend.',
                    style: TextStyle(color: HuntrColors.muted)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in PhotoSubject.values)
                    ActionChip(
                      avatar: Icon(s.icon, size: 18),
                      label: Text(s.label),
                      onPressed: () {
                        app.addMyPhoto(s);
                        Navigator.pop(ctx);
                      },
                    ),
                ]),
              ]),
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
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit profile', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(
                controller: bio,
                maxLines: 3,
                maxLength: 160,
                decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'What should people know about you?'),
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
