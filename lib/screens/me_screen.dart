import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/photo.dart';
import 'my_album_screen.dart';

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
                SizedBox(
                  width: 72,
                  height: 72,
                  child: PhotoArt(
                      photo: app.myPhotos.first, radius: 36, iconSize: 30),
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
            // ---- public profile pictures ----
            Text(
                'PROFILE PHOTOS · ${app.myPhotos.length}/${AppState.maxProfilePhotos}',
                style: text.labelMedium
                    ?.copyWith(color: HuntrColors.muted, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            const Text(
                'Everyone can see these on your profile. Tap one to make it your main photo.',
                style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
              children: [
                for (var i = 0; i < app.myPhotos.length; i++)
                  Stack(fit: StackFit.expand, children: [
                    GestureDetector(
                      onTap: () => app.makeMainPhoto(app.myPhotos[i].id),
                      child: PhotoArt(photo: app.myPhotos[i], iconSize: 28),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: HuntrColors.amber,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text('Main',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    if (app.myPhotos.length > 1)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () =>
                              app.removeProfilePhoto(app.myPhotos[i].id),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 15, semanticLabel: 'Remove photo'),
                          ),
                        ),
                      ),
                  ]),
                if (app.myPhotos.length < AppState.maxProfilePhotos)
                  AddPhotoTile(
                    key: const Key('addProfilePhoto'),
                    onTap: () async {
                      final s = await pickSamplePhoto(context);
                      if (s != null) app.addProfilePhoto(s);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ---- private albums ----
            Row(children: [
              Expanded(
                child: Text('MY ALBUMS · ${app.myAlbums.length}',
                    style: text.labelMedium?.copyWith(
                        color: HuntrColors.muted, letterSpacing: 1.2)),
              ),
              TextButton.icon(
                key: const Key('newAlbum'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New album'),
                onPressed: () async {
                  final name = await promptAlbumName(context);
                  if (name == null || !context.mounted) return;
                  final a = app.createAlbum(name);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MyAlbumScreen(albumId: a.id)));
                },
              ),
            ]),
            const Text(
              'Private and separate from your profile. You choose one to send when you send or accept a chat request.',
              style: TextStyle(color: HuntrColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (app.myAlbums.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No albums yet.'),
              ),
            for (final a in app.myAlbums)
              Card(
                color: HuntrColors.surface,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: SizedBox(
                    width: 52,
                    height: 52,
                    child: a.photos.isEmpty
                        ? const Icon(Icons.photo_library_outlined,
                            color: HuntrColors.muted)
                        : PhotoArt(photo: a.photos.first, iconSize: 20),
                  ),
                  title: Text(a.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${a.photos.length} photos · Private',
                      style: const TextStyle(color: HuntrColors.muted)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MyAlbumScreen(albumId: a.id))),
                ),
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
