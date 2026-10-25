import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/avatar.dart';
import '../widgets/me/me_profile_card.dart';
import '../widgets/me/my_albums_section.dart';
import '../widgets/me/my_story_section.dart';
import '../widgets/me/profile_photos_section.dart';
import '../widgets/me/profile_preview_banner.dart';
import '../theme.dart';
import 'settings_screen.dart';
import '../widgets/profile/edit_profile_sheet.dart';
import '../widgets/page_title.dart';
import 'anonymous_profile_screen.dart' show MyAnonymousProfileScreen;
import 'profile_screen.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  static const _sectionGap = SizedBox(height: 28);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    // privacy, safety and account are in Settings (the gear)
    final top = <Widget>[
      MeProfileCard(
        name: app.myName.isEmpty ? 'You' : app.myName,
        age: app.myAge,
        bio: app.myBio,
        photo: app.defaultPhoto,
        placeholder: ProfileArt(profile: app.myPublicProfile, fontSize: 44),
        showOnline: app.showOnline,
        onEdit: () => showEditProfileSheet(context),
      ),
      const SizedBox(height: 16),
      const MyStorySection(),
      const SizedBox(height: 16),
      // how others see me anonymously (and a new name there)
      if (app.anonymousName != null) ...[
        Material(
          color: HuntrColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: HuntrColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const Key('openAnonymousProfile'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            minVerticalPadding: 16,
            leading:
                Icon(Icons.theater_comedy_outlined, color: HuntrColors.orange),
            title: const Text('Anonymous profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: HuntrColors.muted),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MyAnonymousProfileScreen())),
          ),
        ),
        const SizedBox(height: 16),
      ],
      ProfilePreviewBanner(
        onViewProfile: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileScreen.preview(
              profile: app.myPublicProfile,
              showDistance: app.showDistance,
            ),
          ),
        ),
      ),
    ];
    final sections = <Widget>[
      // ---- public profile pictures (from the backend) ----
      const ProfilePhotosSection(),
      _sectionGap,

      // ---- private albums ----
      const MyAlbumsSection(),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            // wide: the profile on the left, photos and the rest on the right
            constraints: BoxConstraints(maxWidth: wide ? 1180 : 720),
            child: ListView(
              padding:
                  EdgeInsets.fromLTRB(wide ? 32 : 20, 12, wide ? 32 : 20, 32),
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
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen())),
                  ),
                ]),
                const SizedBox(height: 16),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          flex: 2,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: top)),
                      const SizedBox(width: 40),
                      Expanded(
                          flex: 3,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: sections)),
                    ],
                  )
                else ...[
                  ...top,
                  _sectionGap,
                  ...sections,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
