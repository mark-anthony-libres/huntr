import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/social_links.dart';
import '../../theme.dart';

/// The network's logo.
FaIconData socialIcon(SocialNetwork network) => switch (network) {
      SocialNetwork.instagram => FontAwesomeIcons.instagram,
      SocialNetwork.x => FontAwesomeIcons.xTwitter,
      SocialNetwork.facebook => FontAwesomeIcons.facebook,
      SocialNetwork.tiktok => FontAwesomeIcons.tiktok,
    };

/// Their social links on a profile: each network's logo and @username;
/// tapped, their profile there opens (in that app, or the browser).
class SocialLinksRow extends StatelessWidget {
  const SocialLinksRow({super.key, required this.links});

  final SocialLinks links;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final network in SocialNetwork.values)
            if (links[network] case final username?)
              Material(
                key: Key('social-${network.name}'),
                color: HuntrColors.surface,
                shape: const StadiumBorder(
                    side: BorderSide(color: HuntrColors.border)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => launchUrl(network.urlFor(username),
                      mode: LaunchMode.externalApplication),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      FaIcon(socialIcon(network),
                          size: 17, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(network.shown(username),
                          semanticsLabel: '${network.label}: $username',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                    ]),
                  ),
                ),
              ),
        ],
      );
}
