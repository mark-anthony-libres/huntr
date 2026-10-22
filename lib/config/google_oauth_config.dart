import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.webClientId,
    required this.iosClientId,
    required this.androidServerClientId,
    this.backendUrl = '',
  });

  final String webClientId;
  final String iosClientId;
  final String androidServerClientId;

  /// Huntr backend base URL (e.g. http://localhost:18000/api). Overridden by BACKEND_URL; empty = no server verification.
  final String backendUrl;

  /// Set per run target with --dart-define-from-file=`env/dev.json`.
  static const _backendUrlOverride = String.fromEnvironment('BACKEND_URL');

  /// The Huntr backend base URL, or '' when it isn't configured.
  static Future<String> loadBackendUrl() async =>
      (await load()).backendUrl.trim();

  static Future<GoogleOAuthConfig> load() async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/google_oauth.json'),
    ) as Map<String, dynamic>;

    return GoogleOAuthConfig(
      webClientId: json['webClientId'] as String? ?? '',
      iosClientId: json['iosClientId'] as String? ?? '',
      androidServerClientId: json['androidServerClientId'] as String? ?? '',
      backendUrl: _backendUrlOverride.isNotEmpty
          ? _backendUrlOverride
          : json['backendUrl'] as String? ?? '',
    );
  }

  /// The native platform, or null in a browser: on the web Flutter reports the
  /// phone's OS (iOS on an iPhone), but sign-in must use the web client.
  static TargetPlatform? get _nativePlatform =>
      kIsWeb ? null : defaultTargetPlatform;

  String? get clientId => switch (_nativePlatform) {
        TargetPlatform.iOS => _nonEmpty(iosClientId),
        TargetPlatform.android => null,
        _ => _nonEmpty(webClientId),
      };

  String? get serverClientId => switch (_nativePlatform) {
        TargetPlatform.android => _nonEmpty(androidServerClientId),
        _ => null,
      };

  bool get isConfigured => switch (_nativePlatform) {
        TargetPlatform.android => androidServerClientId.trim().isNotEmpty,
        TargetPlatform.iOS => iosClientId.trim().isNotEmpty,
        _ => webClientId.trim().isNotEmpty,
      };

  static String? _nonEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();
}
