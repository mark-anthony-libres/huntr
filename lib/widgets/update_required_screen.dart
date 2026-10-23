import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../services/huntr_backend.dart' show AppRelease;
import '../theme.dart';
import 'profile/gradient_button.dart';

/// Covers the whole app while it's too old ([AppUpdateGate]): checks at
/// start and whenever HUNTR comes back to the screen.
class UpdateGateOverlay extends StatefulWidget {
  const UpdateGateOverlay({super.key, required this.gate, required this.child});

  final AppUpdateGate gate;
  final Widget child;

  @override
  State<UpdateGateOverlay> createState() => _UpdateGateOverlayState();
}

class _UpdateGateOverlayState extends State<UpdateGateOverlay> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    widget.gate.check();
    // back from the store (or from anywhere): maybe it's updated now, or a
    // new release came out meanwhile
    _lifecycle = AppLifecycleListener(onShow: widget.gate.check);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.gate,
        builder: (context, _) => Stack(children: [
          widget.child,
          if (widget.gate.required case final release?)
            Positioned.fill(child: UpdateRequiredScreen(release: release)),
        ]),
      );
}

/// "Time to update": no way past it but updating.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.release});

  final AppRelease release;

  /// Where Update goes: Google Play, the App Store, or (the website) the
  /// page again, which loads the new version.
  Uri? get _target {
    if (kIsWeb) return Uri.base;
    final url = switch (defaultTargetPlatform) {
      TargetPlatform.android => release.playStoreUrl,
      TargetPlatform.iOS => release.appStoreUrl,
      _ => null,
    };
    return url == null ? null : Uri.tryParse(url);
  }

  Future<void> _update(Uri target) => launchUrl(target,
      mode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_self');

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final store = switch (defaultTargetPlatform) {
      _ when kIsWeb => null,
      TargetPlatform.android => 'Google Play',
      TargetPlatform.iOS => 'the App Store',
      _ => null,
    };
    return Material(
      key: const Key('updateRequired'),
      color: HuntrColors.night,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/huntr_logo.png',
                      width: 88,
                      height: 88,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.system_update_rounded,
                          size: 72,
                          color: HuntrColors.orange)),
                ),
                const SizedBox(height: 24),
                const Text('Time to update HUNTR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                    kIsWeb
                        ? 'A new version is ready, with fixes and new '
                            'features. Reload to keep using HUNTR.'
                        : 'A new version is ready, with fixes and new '
                            'features. Update to keep using HUNTR.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15, height: 1.45)),
                const SizedBox(height: 28),
                if (target != null)
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      key: const Key('updateNow'),
                      icon: kIsWeb
                          ? Icons.refresh_rounded
                          : Icons.system_update_rounded,
                      label: kIsWeb
                          ? 'Reload'
                          : store == null
                              ? 'Update now'
                              : 'Update on $store',
                      onPressed: () => _update(target),
                    ),
                  )
                else
                  const Text(
                      'Update HUNTR from where you installed it, then open it '
                      'again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HuntrColors.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
