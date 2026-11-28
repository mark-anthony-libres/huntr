import 'package:flutter/material.dart';

import '../flows/my_profile_photos.dart';
import '../flows/open_person_profile.dart' show openMyProfilePreview;
import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/me/has_place_setting.dart';
import '../widgets/me/me_profile_card.dart';
import '../widgets/me/my_story_button.dart';
import '../widgets/me/settings_group.dart';
import '../widgets/page_title.dart';
import 'anonymous_profile_screen.dart' show MyAnonymousProfileScreen;
import 'edit_profile_screen.dart';
import 'private_albums_screen.dart';
import 'settings_screen.dart';

/// Me: my photos and name (Edit profile, Preview), my story, and a short
/// list (a place, private albums, my anonymous profile). Privacy, safety
/// and the account are in Settings (the gear).
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadPhotos();
    }
  }

  Future<void> _loadPhotos() async {
    final app = AppScope.read(context);
    try {
      await loadMyProfilePhotos(context);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      debugPrint('My photos could not be loaded: $error');
    }
  }

  /// For the photo cache, when a photo's link expired: reloads the list
  /// (fresh links) and returns that photo, or null when it's gone.
  Future<ProfilePhoto?> _refreshPhoto(int photoId) async {
    if (!mounted) return null;
    final list = await loadMyProfilePhotos(context);
    for (final photo in list?.photos ?? const <ProfilePhoto>[]) {
      if (photo.id == photoId) return photo;
    }
    return null;
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    ServicesScope.photoCacheOf(context)?.refresh = _refreshPhoto;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(children: [
                  const Expanded(
                    child: PageTitle('Me',
                        gradient: false,
                        style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  IconButton(
                    key: const Key('openSettings'),
                    tooltip: 'Settings',
                    style: IconButton.styleFrom(
                        backgroundColor: HuntrColors.surface,
                        minimumSize: const Size(44, 44)),
                    // a dot while there's What's new I haven't seen
                    icon: Badge(
                      key: const Key('settingsNewDot'),
                      isLabelVisible: app.whatsNewUnseen,
                      smallSize: 9,
                      backgroundColor: HuntrColors.orange,
                      child: const Icon(Icons.settings_outlined),
                    ),
                    onPressed: () => _push(const SettingsScreen()),
                  ),
                ]),
                const SizedBox(height: 12),
                MeProfileCard(
                  name: app.myName.isEmpty ? 'You' : app.myName,
                  age: app.myAge,
                  bio: app.myBio,
                  photos: app.profilePhotos,
                  maxPhotos: app.maxProfilePhotos,
                  placeholder:
                      ProfileArt(profile: app.myPublicProfile, fontSize: 64),
                  story: const MyStoryButton(),
                  onEdit: () => openEditProfile(context),
                  onPreview: () => openMyProfilePreview(context,
                      showDistance: app.showDistance),
                ),
                const SizedBox(height: 16),
                SettingsGroup(children: [
                  const HasPlaceSetting(),
                  SettingsRow(
                    key: const Key('openPrivateAlbums'),
                    icon: Icons.lock_outline_rounded,
                    title: 'Private albums',
                    subtitle: 'Only people you choose can see them',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: HuntrColors.muted),
                    onTap: () => _push(const PrivateAlbumsScreen()),
                  ),
                  if (app.anonymousName != null)
                    SettingsRow(
                      key: const Key('openAnonymousProfile'),
                      icon: Icons.theater_comedy_outlined,
                      title: 'Anonymous profile',
                      subtitle: 'How you show in anonymous chats',
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: HuntrColors.muted),
                      onTap: () => _push(const MyAnonymousProfileScreen()),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
