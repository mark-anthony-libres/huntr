import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_install/app_install.dart';
import '../theme.dart';

/// "Get the HUNTR app" at the top of Explore on the website: on Android the
/// app to download (until it's on Google Play), elsewhere one tap to install
/// the site where the browser allows it, or the two steps on an iPhone. Not
/// shown in the apps, once installed, or for 14 days after "Not now".
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

/// The website on an Android phone: the app can be downloaded.
bool get _androidWeb =>
    kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Where the Android app is downloaded from (tool/release_apk.sh), until
/// it's on Google Play.
const androidAppPath = '/download/huntr.apk';

/// "Get the HUNTR app": Google Play and the App Store are coming; for now
/// the Android app to download, with how to install it, and on an iPhone how
/// to add the site to the Home Screen.
Future<void> showGetTheAppSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _GetTheApp(),
    );

class _InstallBannerState extends State<InstallBanner> {
  bool _dismissed = AppInstall.dismissedRecently;

  @override
  void initState() {
    super.initState();
    // the browser may offer installing (or finish it) a moment later
    AppInstall.onChange(() {
      if (mounted) setState(() {});
    });
  }

  bool get _visible =>
      !_dismissed &&
      !AppInstall.isInstalled &&
      (_androidWeb || AppInstall.canPrompt || AppInstall.isIos);

  void _notNow() {
    AppInstall.dismiss();
    setState(() => _dismissed = true);
  }

  Future<void> _install() async {
    if (_androidWeb) return showGetTheAppSheet(context);
    if (AppInstall.canPrompt) {
      final installed = await AppInstall.prompt();
      if (mounted) setState(() => _dismissed = installed || _dismissed);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _IosSteps(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        key: const Key('installBanner'),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          gradient: HuntrColors.glowGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/huntr_logo.png',
                width: 44,
                height: 44,
                errorBuilder: (_, __, ___) => const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.download_rounded))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Get the HUNTR app',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                  _androidWeb
                      ? 'Download the Android app. Google Play is coming soon.'
                      : 'Full screen, quicker to open, right on your home screen.',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('installApp'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _install,
            child: Text(_androidWeb
                ? 'Get it'
                : AppInstall.canPrompt
                    ? 'Install'
                    : 'How?'),
          ),
          IconButton(
            key: const Key('installNotNow'),
            tooltip: 'Not now',
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: _notNow,
          ),
        ]),
      ),
    );
  }
}

/// On an iPhone or iPad no button can install it: the two steps.
class _IosSteps extends StatelessWidget {
  const _IosSteps();

  @override
  Widget build(BuildContext context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add HUNTR to your Home Screen',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                SizedBox(height: 16),
                _Step(
                    number: 1,
                    icon: Icons.ios_share_rounded,
                    text: 'Tap Share in the browser bar.'),
                SizedBox(height: 12),
                _Step(
                    number: 2,
                    icon: Icons.add_box_outlined,
                    text: 'Choose "Add to Home Screen", then Add.'),
                SizedBox(height: 16),
                Text('HUNTR then opens full screen, like any app.',
                    style: TextStyle(color: HuntrColors.muted)),
              ]),
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.text});

  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: HuntrColors.orange,
          child: Text('$number',
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: HuntrColors.orange),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]);
}

class _GetTheApp extends StatelessWidget {
  const _GetTheApp();

  Future<void> _download() => launchUrl(Uri.base.resolve(androidAppPath),
      webOnlyWindowName: '_self');

  @override
  Widget build(BuildContext context) {
    final iphone = AppInstall.isIos;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Get the HUNTR app',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 8),
            const Text(
                'HUNTR is coming soon to Google Play and the App Store. '
                'For now, you can download the Android app here.',
                style: TextStyle(color: HuntrColors.muted, height: 1.45)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('downloadAndroidApp'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.android_rounded),
                label: const Text('Download for Android'),
                onPressed: _download,
              ),
            ),
            const SizedBox(height: 22),
            const Text('How to install',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            const _Step(
                number: 1,
                icon: Icons.download_rounded,
                text: 'Tap Download for Android, then open huntr.apk when '
                    'it finishes (from the notification or your Downloads).'),
            const SizedBox(height: 12),
            const _Step(
                number: 2,
                icon: Icons.settings_outlined,
                text: 'If your phone asks, allow your browser to install '
                    'apps ("Install unknown apps", then Allow from this '
                    'source), and go back.'),
            const SizedBox(height: 12),
            const _Step(
                number: 3,
                icon: Icons.install_mobile_rounded,
                text: 'Tap Install. If Play Protect says it doesn\'t '
                    'recognise the app, tap More details, then Install '
                    'anyway: that\'s only because HUNTR isn\'t on Google Play '
                    'yet.'),
            const SizedBox(height: 12),
            const _Step(
                number: 4,
                icon: Icons.login_rounded,
                text: 'Open HUNTR and sign in with the same account.'),
            const SizedBox(height: 14),
            const Text(
                'Updates: when there\'s a new version, HUNTR tells you and '
                'downloads it; open it and tap Update. Your account and '
                'chats stay as they are.',
                style: TextStyle(
                    color: HuntrColors.muted, fontSize: 13, height: 1.45)),
            if (iphone) ...[
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 12),
              const Text('On iPhone',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              const Text(
                  'The App Store version is coming soon. Meanwhile, add '
                  'HUNTR to your Home Screen:',
                  style: TextStyle(color: HuntrColors.muted, height: 1.45)),
              const SizedBox(height: 12),
              const _Step(
                  number: 1,
                  icon: Icons.ios_share_rounded,
                  text: 'Tap Share in the browser bar.'),
              const SizedBox(height: 12),
              const _Step(
                  number: 2,
                  icon: Icons.add_box_outlined,
                  text: 'Choose "Add to Home Screen", then Add.'),
            ],
          ],
        ),
      ),
    );
  }
}
