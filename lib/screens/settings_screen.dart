import 'package:flutter/material.dart';

import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../state/block_state.dart';
import '../state/messaging_state.dart';
import '../widgets/me/anonymous_messaging_setting.dart';
import '../widgets/me/privacy_settings_group.dart';
import '../widgets/me/settings_group.dart';
import '../widgets/profile/deactivate_account.dart';
import '../widgets/profile/log_out.dart';
import '../services/app_icon.dart';
import 'agreement_screen.dart';
import 'appearance_screen.dart';
import 'blocked_users_screen.dart';
import 'feedback_screen.dart';
import 'unmatched_users_screen.dart';

/// Privacy, safety and account, opened from the gear on Me.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _sectionGap = SizedBox(height: 28);

  @override
  Widget build(BuildContext context) {
    final agreements = ServicesScope.agreementsOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: const Key('settingsList'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // ---- explore ----
              const SectionLabel('EXPLORE'),
              const SizedBox(height: 10),
              SettingsGroup(children: [
                SettingsRow(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Show "Find your vibe"',
                  subtitle:
                      'Suggests people near you who want the same. Remembered on this device',
                  trailing: Switch(
                    key: const Key('settingsShowVibeBanner'),
                    value: AppScope.of(context).showVibeBanner,
                    onChanged: (value) =>
                        AppScope.read(context).showVibeBanner = value,
                  ),
                ),
              ]),
              _sectionGap,

              // ---- appearance: theme, and (Android app) the icon ----
              const SectionLabel('APPEARANCE'),
              const SizedBox(height: 10),
              SettingsGroup(children: [
                SettingsRow(
                  key: const Key('openAppearance'),
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: AppIcons.supported
                      ? '${AppScope.of(context).appearance.value.name} theme '
                          'and app icon'
                      : '${AppScope.of(context).appearance.value.name} theme',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AppearanceScreen())),
                ),
              ]),
              _sectionGap,

              // ---- privacy ----
              const SectionLabel('PRIVACY'),
              const SizedBox(height: 10),
              // who I've blocked or unmatched, with the visibility switches
              PrivacySettingsGroup(moreRows: [
                if (BlockScope.of(context) != null)
                  SettingsRow(
                    key: const Key('openBlockedUsers'),
                    icon: Icons.block_rounded,
                    title: 'Blocked users',
                    subtitle:
                        'People you blocked, and when you can unblock them',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen())),
                  ),
                if (MessagingScope.of(context) != null)
                  SettingsRow(
                    key: const Key('openUnmatchedUsers'),
                    icon: Icons.person_remove_outlined,
                    title: 'Unmatched users',
                    subtitle: 'People you unmatched. Remove them to see each '
                        'other again',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const UnmatchedUsersScreen())),
                  ),
              ]),
              _sectionGap,

              // ---- anonymous messaging ----
              const SectionLabel('ANONYMOUS MESSAGING'),
              const SizedBox(height: 10),
              const AnonymousMessagingSetting(),
              _sectionGap,

              // ---- safety ----
              const SectionLabel('SAFETY'),
              const SizedBox(height: 10),
              SettingsGroup(children: [
                const SettingsRow(
                  icon: Icons.shield_outlined,
                  title: 'Safety tips',
                  subtitle:
                      'Meet in public places and tell a friend where you are going',
                ),
                if (agreements != null)
                  SettingsRow(
                    key: const Key('openCommunityGuidelines'),
                    icon: Icons.handshake_outlined,
                    title: 'Community Guidelines',
                    subtitle: 'How we keep HUNTR kind, respectful and safe',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AgreementScreen.communityGuidelines(
                            agreements: agreements))),
                  ),
                if (agreements != null)
                  SettingsRow(
                    key: const Key('openAgreement'),
                    icon: Icons.description_outlined,
                    title: 'Terms & guidelines',
                    subtitle: 'The agreement you accepted',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            AgreementScreen(agreements: agreements))),
                  ),
              ]),
              _sectionGap,

              // ---- support ----
              if (ServicesScope.feedbackOf(context) case final feedback?) ...[
                const SectionLabel('SUPPORT'),
                const SizedBox(height: 10),
                SettingsGroup(children: [
                  SettingsRow(
                    key: const Key('openSendFeedback'),
                    icon: Icons.lightbulb_outline_rounded,
                    title: 'Send feedback',
                    subtitle: 'Suggest an idea or report a problem',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SendFeedbackScreen(service: feedback))),
                  ),
                  SettingsRow(
                    key: const Key('openMyFeedback'),
                    icon: Icons.forum_outlined,
                    title: 'My feedback',
                    subtitle: 'What you sent, and where it stands',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MyFeedbackScreen(service: feedback))),
                  ),
                ]),
                _sectionGap,
              ],

              // ---- account ----
              const SectionLabel('ACCOUNT'),
              const SizedBox(height: 10),
              SettingsGroup(children: [
                SettingsRow(
                  key: const Key('logOut'),
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  subtitle: 'Sign out of Huntr on this device',
                  onTap: () => confirmAndLogOut(context),
                ),
                SettingsRow(
                  key: const Key('deactivateAccount'),
                  icon: Icons.delete_outline,
                  title: 'Deactivate account',
                  subtitle: 'Permanently deletes your account and data',
                  danger: true,
                  onTap: () => confirmAndDeactivateAccount(context),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
