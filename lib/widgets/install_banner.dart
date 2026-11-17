import 'package:flutter/material.dart';

import '../services/app_install/app_install.dart';
import '../theme.dart';

/// "Get the HUNTR app" over Explore on the website, once a visit: one tap to
/// install the site where the browser allows it (Android phones included:
/// the Android app's download isn't offered here), or the steps on an
/// iPhone. Not shown in the apps, once installed, or for 14 days after "Not
/// now". Takes no room itself.
class InstallInvite extends StatefulWidget {
  const InstallInvite({super.key});

  @override
  State<InstallInvite> createState() => _InstallInviteState();
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

class _InstallInviteState extends State<InstallInvite> {
  /// Asked already this visit (Explore can be opened again).
  static bool _asked = false;

  @override
  void initState() {
    super.initState();
    // the browser may offer installing a moment later
    AppInstall.onChange(() {
      if (mounted) _maybeAsk();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAsk();
    });
  }

  void _maybeAsk() {
    if (_asked || AppInstall.dismissedRecently || !canInstallWebsite) return;
    // only over Explore itself, not over a screen opened on top
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _asked = true;
    showDialog<void>(
      context: context,
      builder: (_) => const _InstallDialog(),
    ).then((_) {
      // closed without installing (Not now, outside, back): not again soon
      if (!AppInstall.isInstalled) AppInstall.dismiss();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The invitation: the logo, why, and Install (the browser's dialog) or, on
/// an iPhone, the steps right there.
class _InstallDialog extends StatelessWidget {
  const _InstallDialog();

  @override
  Widget build(BuildContext context) {
    final steps = !AppInstall.canPrompt;
    return Dialog(
      key: const Key('installInvite'),
      backgroundColor: HuntrColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: HuntrColors.orange.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // the top: the theme's glow behind the logo
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                  decoration: BoxDecoration(gradient: HuntrColors.glowGradient),
                  child: Column(children: [
                    // whole, at its own shape (wider than tall; its
                    // artwork reaches the edges, so no rounded clip)
                    Image.asset('assets/huntr_logo.png',
                        key: const Key('installLogo'),
                        height: 64,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            height: 64,
                            child: Icon(Icons.download_rounded, size: 36))),
                    const SizedBox(height: 16),
                    const Text('Get the HUNTR app',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 22)),
                    const SizedBox(height: 6),
                    const Text(
                        'Full screen, quicker to open, right on your home '
                        'screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white70, fontSize: 14, height: 1.4)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: steps
                      ? const _IosStepList()
                      : FilledButton.icon(
                          key: const Key('installApp'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52)),
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await AppInstall.prompt();
                            navigator.pop();
                          },
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Install'),
                        ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      24, steps ? 8 : 0, 24, steps ? 24 : 16),
                  // the iPhone's only button: full and in the accent;
                  // otherwise a quiet Not now under Install
                  child: steps
                      ? FilledButton.icon(
                          key: const Key('installNotNow'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52)),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Got it'),
                        )
                      : TextButton(
                          key: const Key('installNotNow'),
                          style: TextButton.styleFrom(
                              foregroundColor: HuntrColors.muted,
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Not now'),
                        ),
                ),
              ]),
        ),
      ),
    );
  }
}

/// On an iPhone or iPad no button can install it: the steps.
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
                _IosStepList(),
              ]),
        ),
      );
}

/// Adding it to the Home Screen on an iPhone, step by step.
class _IosStepList extends StatelessWidget {
  const _IosStepList();

  @override
  Widget build(BuildContext context) => const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // newer Safari keeps Share under ⋯ (older ones show it in
            // the bar)
            _Step(
                number: 1,
                icon: Icons.more_horiz_rounded,
                text: 'Tap ⋯ at the bottom right, then Share. (Older '
                    'iPhones: tap Share in the browser bar.)'),
            SizedBox(height: 12),
            _Step(
                number: 2,
                icon: Icons.add_box_outlined,
                text: 'Choose "Add to Home Screen". Not in the list? '
                    'Tap View More.'),
            SizedBox(height: 12),
            _Step(
                number: 3,
                icon: Icons.check_circle_outline_rounded,
                text: 'Keep "Open as Web App" on, then tap Add.'),
            SizedBox(height: 16),
            Text('HUNTR then opens full screen, like any app.',
                style: TextStyle(color: HuntrColors.muted)),
          ]);
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
