import 'package:flutter/material.dart';

import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../state/block_state.dart';
import '../state/messaging_state.dart';
import '../widgets/me/anonymous_messaging_setting.dart';
import '../widgets/me/notification_settings_group.dart';
import '../widgets/me/nsfw_setting.dart';
import '../widgets/me/privacy_settings_group.dart';
import '../widgets/me/settings_group.dart';
import '../widgets/profile/deactivate_account.dart';
import '../widgets/profile/log_out.dart';
import '../services/app_icon.dart';
import '../theme.dart';
import 'agreement_screen.dart';
import 'appearance_screen.dart';
import 'blocked_users_screen.dart';
import 'feedback_screen.dart';
import 'unmatched_users_screen.dart';
import 'whats_new_screen.dart';
import '../config/store_build.dart';

/// Privacy, safety and account, opened from the gear on Me. A search box at
/// the top keeps only the settings whose title or subtext has what's typed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  final _results = SettingsSearchResults();

  @override
  void dispose() {
    _search.dispose();
    _results.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                key: const Key('settingsSearch'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search settings',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('settingsSearchClear'),
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
            Expanded(
              child: SettingsSearch(
                query: query,
                results: _results,
                child: _list(context, query),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, String query) {
    final agreements = ServicesScope.agreementsOf(context);
    return ListView(
      key: const Key('settingsList'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      children: [
        // nothing matches what's typed
        if (query.isNotEmpty)
          ListenableBuilder(
            listenable: _results,
            builder: (context, _) => _results.any
                ? const SizedBox.shrink()
                : Padding(
                    key: const Key('settingsNoMatch'),
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text('No settings match "${_search.text.trim()}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: HuntrColors.muted)),
                  ),
          ),

        // ---- appearance: theme, and (Android app) the icon ----
        SettingsSection(
          label: 'APPEARANCE',
          child: SettingsGroup(children: [
            SettingsRow(
              key: const Key('openAppearance'),
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: AppIcons.supported
                  ? '${AppScope.of(context).appearance.value.name} theme '
                      'and app icon'
                  : '${AppScope.of(context).appearance.value.name} theme',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppearanceScreen())),
            ),
          ]),
        ),

        // ---- privacy: the visibility switches, and who I've blocked or
        // unmatched ----
        SettingsSection(
          label: 'PRIVACY',
          child: PrivacySettingsGroup(moreRows: [
            if (BlockScope.of(context) != null)
              SettingsRow(
                key: const Key('openBlockedUsers'),
                icon: Icons.block_rounded,
                title: 'Blocked users',
                subtitle: 'People you blocked, and when you can unblock them',
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
        ),

        // ---- content: NSFW ----
        // a store build shows no NSFW content, so nothing to set
        if (!isStoreBuild)
          const SettingsSection(label: 'CONTENT', child: NsfwSetting()),

        // ---- notifications: each kind, and this device ----
        const SettingsSection(
            label: 'NOTIFICATIONS', child: NotificationSettingsGroup()),

        // ---- anonymous messaging ----
        const SettingsSection(
            label: 'ANONYMOUS MESSAGING', child: AnonymousMessagingSetting()),

        // ---- safety ----
        SettingsSection(
          label: 'SAFETY',
          child: SettingsGroup(children: [
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
                subtitle: 'The rules for using HUNTR',
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
                    builder: (_) => AgreementScreen(agreements: agreements))),
              ),
            if (agreements != null)
              SettingsRow(
                key: const Key('openPrivacyPolicy'),
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'What we collect and how we use it',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        AgreementScreen.privacyPolicy(agreements: agreements))),
              ),
          ]),
        ),

        // ---- support ----
        if (ServicesScope.feedbackOf(context) case final feedback?) ...[
          SettingsSection(
            label: 'SUPPORT',
            child: SettingsGroup(children: [
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
          ),
        ],

        // ---- what's new ----
        if (ServicesScope.changelogOf(context) != null)
          SettingsSection(
            label: 'ABOUT',
            child: SettingsGroup(children: [
              SettingsRow(
                key: const Key('openWhatsNew'),
                icon: Icons.auto_awesome_outlined,
                title: "What's new",
                subtitle: 'New features and fixes in HUNTR',
                trailing: AppScope.of(context).whatsNewUnseen
                    ? Badge(
                        key: const Key('whatsNewDot'),
                        smallSize: 10,
                        backgroundColor: HuntrColors.orange)
                    : null,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WhatsNewScreen())),
              ),
            ]),
          ),

        // ---- account ----
        SettingsSection(
          label: 'ACCOUNT',
          child: SettingsGroup(children: [
            SettingsRow(
              key: const Key('logOut'),
              icon: Icons.logout_rounded,
              title: 'Log out',
              subtitle: 'Sign out of HUNTR on this device',
              onTap: () => confirmAndLogOut(context),
            ),
            SettingsRow(
              key: const Key('deactivateAccount'),
              icon: Icons.delete_outline,
              title: 'Delete account',
              subtitle: 'Permanently deletes your account and data',
              danger: true,
              onTap: () => confirmAndDeactivateAccount(context),
            ),
          ]),
        ),
      ],
    );
  }
}
