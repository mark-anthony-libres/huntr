import 'package:flutter/material.dart';

import '../services/app_install/app_install.dart';
import '../theme.dart';

/// "Get the HUNTR app" at the top of Explore on the website: one tap to
/// install the site where the browser allows it (Android phones included:
/// the Android app's download isn't offered here), or the two steps on an
/// iPhone. Not shown in the apps, once installed, or for 14 days after "Not
/// now".
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

/// The website can be installed as an app here (and isn't yet): with the
/// browser's one tap, or the steps on an iPhone.
bool get canInstallWebsite =>
    !AppInstall.isInstalled && (AppInstall.canPrompt || AppInstall.isIos);

/// Installs the website as an app: the browser's dialog where it has one
/// (true when installed), otherwise the iPhone's two steps.
Future<bool> installWebsite(BuildContext context) async {
  if (AppInstall.canPrompt) return AppInstall.prompt();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _IosSteps(),
  );
  return false;
}

/// "Install HUNTR" (the sign-in page): installs the website as an app, where
/// it can be (it shows once the browser offers it).
class InstallWebsiteButton extends StatefulWidget {
  const InstallWebsiteButton(
      {super.key, this.fontSize = 16, this.style, this.leadingGap = 0});

  final double fontSize;

  /// How it looks (a plain text button without one).
  final ButtonStyle? style;

  /// Space before it, only while it shows (so what's beside it stays
  /// centered when it doesn't).
  final double leadingGap;

  @override
  State<InstallWebsiteButton> createState() => _InstallWebsiteButtonState();
}

class _InstallWebsiteButtonState extends State<InstallWebsiteButton> {
  @override
  void initState() {
    super.initState();
    // the browser may offer installing (or finish it) a moment later
    AppInstall.onChange(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!canInstallWebsite) return const SizedBox.shrink();
    final button = TextButton.icon(
      key: const Key('signInInstallWebsite'),
      style: widget.style,
      onPressed: () async {
        await installWebsite(context);
        if (mounted) setState(() {});
      },
      icon: const Icon(Icons.install_mobile_rounded, size: 20),
      label: Text('Install HUNTR',
          style: TextStyle(
              fontSize: widget.fontSize, fontWeight: FontWeight.w700)),
    );
    return widget.leadingGap == 0
        ? button
        : Padding(
            padding: EdgeInsets.only(left: widget.leadingGap), child: button);
  }
}

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

  bool get _visible => !_dismissed && canInstallWebsite;

  void _notNow() {
    AppInstall.dismiss();
    setState(() => _dismissed = true);
  }

  Future<void> _install() async {
    final installed = await installWebsite(context);
    if (mounted) setState(() => _dismissed = installed || _dismissed);
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
        // phones: the button on its own row under the text (beside it,
        // the text gets squeezed); wider screens: all on one row
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 520;
          final logo = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/huntr_logo.png',
                width: 44,
                height: 44,
                errorBuilder: (_, __, ___) => const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.download_rounded))),
          );
          final text = Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: narrow ? 4 : 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Get the HUNTR app',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    const Text(
                        'Full screen, quicker to open, right on your home screen.',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            height: 1.35)),
                  ]),
            ),
          );
          final button = FilledButton.icon(
            key: const Key('installApp'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _install,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(AppInstall.canPrompt ? 'Install' : 'How?'),
          );
          final close = IconButton(
            key: const Key('installNotNow'),
            tooltip: 'Not now',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: _notNow,
          );
          if (!narrow) {
            return Row(children: [
              logo,
              const SizedBox(width: 12),
              text,
              const SizedBox(width: 8),
              button,
              close,
            ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  logo,
                  const SizedBox(width: 12),
                  text,
                  close,
                ]),
                const SizedBox(height: 10),
                Padding(
                    padding: const EdgeInsets.only(right: 8), child: button),
              ]);
        }),
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
