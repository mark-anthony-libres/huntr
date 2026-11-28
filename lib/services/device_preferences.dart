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

  /// The reactions on the chat's emoji bar, in their order; null until
  /// changed.
  Future<List<String>?> readQuickReactions();
  Future<void> saveQuickReactions(List<String> reactions);

  /// Explore's filters (ExploreFilters.toJson, as JSON); null until set.
  Future<String?> readExploreFilters();
  Future<void> saveExploreFilters(String json);

  /// The voice messages I received and played here (their ids, oldest
  /// first); empty until one was played.
  Future<List<int>> readPlayedVoices();
  Future<void> savePlayedVoices(List<int> messageIds);
}

/// Kept in the platform's secure storage, like the session token (the one
/// storage the app already uses on every platform, web included).
class SecureDevicePreferences implements DevicePreferences {
  const SecureDevicePreferences();

  static const _themeKey = 'huntr_theme';
  static const _exploreLayoutKey = 'huntr_explore_layout';
  static const _quickReactionsKey = 'huntr_quick_reactions';
  static const _playedVoicesKey = 'huntr_played_voices';
  static const _exploreFiltersKey = 'huntr_explore_filters';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> readThemeId() => _storage.read(key: _themeKey);

  @override
  Future<void> saveThemeId(String id) =>
      _storage.write(key: _themeKey, value: id);

  @override
  Future<String?> readExploreLayout() => _storage.read(key: _exploreLayoutKey);

  @override
  Future<void> saveExploreLayout(String name) =>
      _storage.write(key: _exploreLayoutKey, value: name);

  @override
  Future<String?> readExploreFilters() =>
      _storage.read(key: _exploreFiltersKey);

  @override
  Future<void> saveExploreFilters(String json) =>
      _storage.write(key: _exploreFiltersKey, value: json);

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
}
