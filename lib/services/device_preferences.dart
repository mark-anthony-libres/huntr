import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Choices remembered on this device between launches (not on the account):
/// they stay after the app is closed, also when signed out.
abstract class DevicePreferences {
  /// Whether "Find your vibe" shows on Explore; null until it was changed.
  Future<bool?> readShowVibeBanner();
  Future<void> saveShowVibeBanner(bool show);

  /// The chosen theme's id (see huntrPalettes); null until one was chosen.
  Future<String?> readThemeId();
  Future<void> saveThemeId(String id);

  /// Turning notifications on was offered on this device (once).
  Future<bool> readNotificationsOffered();
  Future<void> saveNotificationsOffered();
}

/// Kept in the platform's secure storage, like the session token (the one
/// storage the app already uses on every platform, web included).
class SecureDevicePreferences implements DevicePreferences {
  const SecureDevicePreferences();

  static const _showVibeBannerKey = 'huntr_show_vibe_banner';
  static const _themeKey = 'huntr_theme';
  static const _notificationsOfferedKey = 'huntr_notifications_offered';
  static const _storage = FlutterSecureStorage();

  @override
  Future<bool?> readShowVibeBanner() async =>
      switch (await _storage.read(key: _showVibeBannerKey)) {
        'true' => true,
        'false' => false,
        _ => null,
      };

  @override
  Future<void> saveShowVibeBanner(bool show) =>
      _storage.write(key: _showVibeBannerKey, value: '$show');

  @override
  Future<String?> readThemeId() => _storage.read(key: _themeKey);

  @override
  Future<bool> readNotificationsOffered() async =>
      await _storage.read(key: _notificationsOfferedKey) == 'true';

  @override
  Future<void> saveNotificationsOffered() =>
      _storage.write(key: _notificationsOfferedKey, value: 'true');

  @override
  Future<void> saveThemeId(String id) =>
      _storage.write(key: _themeKey, value: id);
}
