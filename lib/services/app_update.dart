import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show AppRelease;

/// Whether this app is too old to use: the backend names the build everyone
/// must have (APP_LATEST_BUILD), and an older one is blocked until updated.
/// When either can't be known (offline, no build number), nobody is blocked.
class AppUpdateGate extends ChangeNotifier {
  AppUpdateGate({Future<int?> Function()? currentBuild, this.fetchRelease})
      : _currentBuild = currentBuild ?? _installedBuild;

  final Future<int?> Function() _currentBuild;

  /// The backend's answer (tests use their own).
  final Future<AppRelease> Function()? fetchRelease;

  AppRelease? _required;

  /// The release to update to, while this app is too old (null: it's fine).
  AppRelease? get required => _required;

  bool _checking = false;

  /// Asks the backend again (at start, and on coming back to the app).
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      final mine = await _currentBuild();
      final release = await (fetchRelease ?? _fetch)();
      final tooOld =
          mine != null && release.latestBuild > 0 && mine < release.latestBuild;
      final next = tooOld ? release : null;
      if ((next == null) != (_required == null)) {
        _required = next;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Update check skipped: $error');
    } finally {
      _checking = false;
    }
  }

  static Future<AppRelease> _fetch() async => backend.fetchAppRelease(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl());

  /// This build's number (the +N of pubspec's version), read once.
  static Future<int?> _installedBuild() => _installed ??=
      PackageInfo.fromPlatform().then((info) => int.tryParse(info.buildNumber));
  static Future<int?>? _installed;
}
