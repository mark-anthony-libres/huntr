import 'package:flutter/material.dart';

import '../services/app_install/app_install.dart';
import '../theme.dart';

/// "Get the HUNTR app" at the top of Explore on the website: one tap to
/// install where the browser allows it, or the two steps on an iPhone. Not
/// shown in the apps, once installed, or for 14 days after "Not now".
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
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

  bool get _visible =>
      !_dismissed &&
      !AppInstall.isInstalled &&
      (AppInstall.canPrompt || AppInstall.isIos);

  void _notNow() {
    AppInstall.dismiss();
    setState(() => _dismissed = true);
  }

  Future<void> _install() async {
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
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Get the HUNTR app',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 2),
              Text('Full screen, quicker to open, right on your home screen.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5)),
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
            child: Text(AppInstall.canPrompt ? 'Install' : 'How?'),
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
