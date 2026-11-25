import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Choices remembered on this device between launches (not on the account):
/// they stay after the app is closed, also when signed out.
abstract class DevicePreferences {
  /// The chosen theme's id (see huntrPalettes); null until one was chosen.
  Future<String?> readThemeId();
  Future<void> saveThemeId(String id);

  /// How Explore lays people out (ExploreLayout's name); null until chosen.
  Future<String?> readExploreLayout();
  Future<void> saveExploreLayout(String name);

  /// Turning notifications on was offered on this device (once).
  Future<bool> readNotificationsOffered();
  Future<void> saveNotificationsOffered();

  /// The reactions on the chat's emoji bar, in their order; null until
  /// changed.
  Future<List<String>?> readQuickReactions();
  Future<void> saveQuickReactions(List<String> reactions);

  /// The voice messages I received and played here (their ids, oldest
  /// first); empty until one was played.
  Future<List<int>> readPlayedVoices();
  Future<void> savePlayedVoices(List<int> messageIds);

  /// The places I roamed last (Roam's Recent), newest first, as saved
  /// (each a JSON object); empty until I roamed.
  Future<List<Map<String, dynamic>>> readRecentRoams();
  Future<void> saveRecentRoams(List<Map<String, dynamic>> places);
}

/// Kept in the platform's secure storage, like the session token (the one
/// storage the app already uses on every platform, web included).
class SecureDevicePreferences implements DevicePreferences {
  const SecureDevicePreferences();

  static const _themeKey = 'huntr_theme';
  static const _notificationsOfferedKey = 'huntr_notifications_offered';
  static const _exploreLayoutKey = 'huntr_explore_layout';
  static const _quickReactionsKey = 'huntr_quick_reactions';
  static const _playedVoicesKey = 'huntr_played_voices';
  static const _recentRoamsKey = 'huntr_recent_roams';
  static const _storage = FlutterSecureStorage();

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

  @override
  Future<String?> readExploreLayout() => _storage.read(key: _exploreLayoutKey);

  @override
  Future<void> saveExploreLayout(String name) =>
      _storage.write(key: _exploreLayoutKey, value: name);

  @override
  Future<List<String>?> readQuickReactions() async {
    final saved = await _storage.read(key: _quickReactionsKey);
    if (saved == null) return null;
    try {
      return [for (final e in jsonDecode(saved) as List) e as String];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveQuickReactions(List<String> reactions) =>
      _storage.write(key: _quickReactionsKey, value: jsonEncode(reactions));

  @override
  Future<List<int>> readPlayedVoices() async {
    final saved = await _storage.read(key: _playedVoicesKey);
    if (saved == null) return const [];
    try {
      return [for (final id in jsonDecode(saved) as List) id as int];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> savePlayedVoices(List<int> messageIds) =>
      _storage.write(key: _playedVoicesKey, value: jsonEncode(messageIds));

  @override
  Future<List<Map<String, dynamic>>> readRecentRoams() async {
    final saved = await _storage.read(key: _recentRoamsKey);
    if (saved == null) return const [];
    try {
      return [
        for (final place in jsonDecode(saved) as List)
          if (place is Map<String, dynamic>) place
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveRecentRoams(List<Map<String, dynamic>> places) =>
      _storage.write(key: _recentRoamsKey, value: jsonEncode(places));
}
