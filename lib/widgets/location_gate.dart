import 'dart:async';

import 'package:flutter/material.dart';

import '../services/location_permission.dart';
import '../theme.dart';

/// Huntr needs the device location: while [enforce] is on (signed in, past
/// sign-in and the agreement) the app underneath is covered by
/// [LocationRequiredScreen] until location is allowed. It checks again when
/// the app comes back to the foreground (e.g. from Settings) and every few
/// seconds while open, so access taken away later is noticed too. The app
/// underneath stays as it was (session, open chats), and comes back by
/// itself once location is allowed.
class LocationGate extends StatefulWidget {
  const LocationGate({
    super.key,
    required this.access,
    required this.enforce,
    required this.child,
    this.onRevoked,
    this.onGranted,
    this.recheckEvery = const Duration(seconds: 10),
  });

  final LocationAccess access;
  final bool enforce;
  final Widget child;

  /// Location was allowed, and now isn't (e.g. turned off in Settings).
  final VoidCallback? onRevoked;

  /// Location is allowed now, after it wasn't.
  final VoidCallback? onGranted;

  /// Also re-checked this often while the app is open (browsers and desktops
  /// don't tell the app when a permission changes).
  final Duration recheckEvery;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate> {
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  LocationAccessStatus _last = LocationAccessStatus.unknown;

  @override
  void initState() {
    super.initState();
    _last = widget.access.status;
    widget.access.addListener(_changed);
    _lifecycle = AppLifecycleListener(
        onResume: widget.access.refresh, onShow: widget.access.refresh);
    _sync();
  }

  @override
  void didUpdateWidget(LocationGate old) {
    super.didUpdateWidget(old);
    if (old.access != widget.access) {
      old.access.removeListener(_changed);
      widget.access.addListener(_changed);
    }
    if (old.enforce != widget.enforce) _sync();
  }

  /// Checking only matters (and only runs) while it's enforced.
  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.enforce) return;
    unawaited(widget.access.refresh());
    _timer =
        Timer.periodic(widget.recheckEvery, (_) => widget.access.refresh());
  }

  void _changed() {
    final now = widget.access.status;
    final was = _last;
    _last = now;
    if (was == LocationAccessStatus.granted &&
        now != LocationAccessStatus.granted) {
      widget.onRevoked?.call();
    } else if (was != LocationAccessStatus.granted &&
        now == LocationAccessStatus.granted) {
      widget.onGranted?.call();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.access.removeListener(_changed);
    _lifecycle.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.access.status;
    final blocked = widget.enforce && status != LocationAccessStatus.granted;
    return Stack(children: [
      // kept underneath (not rebuilt), but can't be used or focused
      ExcludeFocus(
        excluding: blocked,
        child: IgnorePointer(ignoring: blocked, child: widget.child),
      ),
      if (blocked)
        Positioned.fill(
          child: status == LocationAccessStatus.unknown
              ? const ColoredBox(
                  key: Key('locationChecking'),
                  color: HuntrColors.night,
                  child: Center(child: CircularProgressIndicator()))
              : LocationRequiredScreen(access: widget.access),
        ),
    ]);
  }
}

/// Location is required to use Huntr: why, and how to allow it (the system
/// dialog while it can still be shown, else the device or browser settings).
class LocationRequiredScreen extends StatelessWidget {
  const LocationRequiredScreen({super.key, required this.access});

  final LocationAccess access;

  @override
  Widget build(BuildContext context) {
    final blocked = access.status == LocationAccessStatus.blocked;
    final settings = access.permissions.canOpenSettings;
    final String message;
    if (blocked) {
      message = settings
          ? 'Location access is turned off for Huntr. Open Settings, allow '
              'location for Huntr, then come back.'
          : 'Location access is blocked for this site. Click the lock icon '
              'next to the address bar, allow location, then reload the page.';
    } else if (access.justDenied) {
      message = 'You didn’t allow location. Huntr needs it to show you '
          'people nearby, so it can’t be used without it.';
    } else {
      message = 'Huntr shows you people nearby and how far away they are, '
          'so it needs your location to work.';
    }
    return Material(
      key: const Key('locationRequired'),
      color: HuntrColors.night,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HuntrColors.orange.withValues(alpha: 0.12),
                    border: Border.all(
                        color: HuntrColors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                      blocked
                          ? Icons.location_off_rounded
                          : Icons.location_on_rounded,
                      size: 46,
                      color: HuntrColors.orange),
                ),
                const SizedBox(height: 28),
                const Text('Location is required',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(message,
                    key: const Key('locationRequiredMessage'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: HuntrColors.muted, fontSize: 15, height: 1.45)),
                const SizedBox(height: 32),
                if (!blocked)
                  _Wide(FilledButton.icon(
                    key: const Key('enableLocation'),
                    onPressed: access.request,
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('Enable Location'),
                  ))
                else if (settings)
                  _Wide(FilledButton.icon(
                    key: const Key('openLocationSettings'),
                    onPressed: access.openSettings,
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Open Settings'),
                  )),
                if (blocked) ...[
                  const SizedBox(height: 10),
                  // came back with it allowed (or the browser page wasn't
                  // reloaded): check now
                  _Wide(OutlinedButton(
                    key: const Key('recheckLocation'),
                    onPressed: access.refresh,
                    child: const Text('I’ve allowed it'),
                  )),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wide extends StatelessWidget {
  const _Wide(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: child,
      );
}
