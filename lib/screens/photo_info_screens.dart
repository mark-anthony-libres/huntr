import 'package:flutter/material.dart';

import '../config/store_build.dart';
import '../widgets/info_page.dart';

/// About profile photos (the ⓘ beside Profile photos on Me): who sees
/// them, how to manage them, and what isn't allowed in them.
class ProfilePhotosInfoScreen extends StatelessWidget {
  const ProfilePhotosInfoScreen({super.key});

  @override
  Widget build(BuildContext context) => InfoPage(
        title: 'Profile photos',
        listKey: const Key('profilePhotosInfo'),
        children: [
          const InfoIntro('Everyone on HUNTR can see your profile photos.'),
          const SizedBox(height: 28),
          const InfoHeading('Managing your photos'),
          const SizedBox(height: 12),
          const InfoCard(children: [
            InfoPoint(
              icon: Icons.touch_app_outlined,
              title: 'Tap a photo',
              text: 'View it, crop it, remove it, or make it your main photo.',
            ),
            infoDivider,
            InfoPoint(
              icon: Icons.drag_indicator_rounded,
              title: 'Hold and drag',
              text: 'Rearrange your photos. The first one is your main photo.',
            ),
          ]),
          const SizedBox(height: 28),
          const InfoHeading('Not allowed'),
          const SizedBox(height: 12),
          const InfoCard(children: [
            InfoBullet('Nudity or sexual content'),
            InfoBullet('Anyone under 18'),
            InfoBullet("Someone else's photos without their permission"),
            InfoBullet('Violence, hate, or anything illegal'),
          ]),
          const SizedBox(height: 12),
          const InfoIntro('Photos that break these rules are removed.'),
          const SizedBox(height: 16),
          InfoLinkButton(
            label: 'Community Guidelines',
            url: communityGuidelines(
                section: '7-keep-photos-videos-and-albums-appropriate'),
          ),
        ],
      );
}

/// About albums (the ⓘ beside My albums on Me): who sees them, how they're
/// shared, and the rules for what's in them.
class AlbumsInfoScreen extends StatelessWidget {
  const AlbumsInfoScreen({super.key});

  @override
  Widget build(BuildContext context) => InfoPage(
        title: 'Albums',
        listKey: const Key('albumsInfo'),
        children: [
          const InfoIntro('Albums are private and separate from your profile. '
              'Only people you share one with can see it.'),
          const SizedBox(height: 28),
          const InfoHeading('How they work'),
          const SizedBox(height: 12),
          InfoCard(children: [
            const InfoPoint(
              icon: Icons.add_photo_alternate_outlined,
              title: 'New album',
              text: 'Make an album and add photos to it. Tap an album to '
                  'change it.',
            ),
            infoDivider,
            const InfoPoint(
              icon: Icons.send_outlined,
              title: 'Sharing',
              text: 'When you send or accept a chat request, you choose an '
                  'album to share with that person.',
            ),
            if (!isStoreBuild) ...[
              infoDivider,
              const InfoPoint(
                icon: Icons.visibility_off_outlined,
                title: 'NSFW warning',
                text: 'With Show NSFW warning on Yes, albums show a warning '
                    'before they open.',
              ),
            ],
          ]),
          const SizedBox(height: 28),
          const InfoHeading('Rules'),
          const SizedBox(height: 12),
          const InfoCard(children: [
            InfoBullet('Only share with people who want to see it'),
            InfoBullet('Only photos you have the right to share'),
            InfoBullet('Never anyone under 18'),
            InfoBullet("Never share someone else's album outside HUNTR"),
          ]),
          const SizedBox(height: 16),
          InfoLinkButton(
            label: 'Community Guidelines',
            url: communityGuidelines(
                section: '7-keep-photos-videos-and-albums-appropriate'),
          ),
        ],
      );
}
