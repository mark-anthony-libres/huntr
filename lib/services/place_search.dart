import 'dart:convert';

import 'package:http/http.dart' as http;

import '../widgets/explore/explore_map.dart' show MapTiles;

/// A place found by name (or at a spot on the map), for Roam.
class Place {
  const Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.detail,
  });

  /// "Shibuya"
  final String name;

  /// "Tokyo, Japan" (null when there's nothing more to say).
  final String? detail;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (detail != null) 'detail': detail,
        'lat': latitude,
        'lng': longitude,
      };

  static Place? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final lat = json['lat'], lng = json['lng'], name = json['name'];
    if (lat is! num || lng is! num || name is! String) return null;
    return Place(
        name: name,
        detail: json['detail'] as String?,
        latitude: lat.toDouble(),
        longitude: lng.toDouble());
  }
}

/// Finding places for Roam: MapTiler's place search (the same key as the
/// map's tiles), as you type, and the name of a spot picked on the map.
/// Without a key there's no search (picking on the map still works).
class PlaceSearch {
  PlaceSearch({String? key, http.Client? client})
      : _key = key ?? MapTiles.mapTilerKey,
        _client = client;

  final String _key;
  final http.Client? _client;

  bool get available => _key.isNotEmpty;

  /// Places matching what's typed (2 letters or more), best first.
  Future<List<Place>> search(String query) async {
    final q = query.trim();
    if (!available || q.length < 2) return const [];
    final found = await _get('/geocoding/${Uri.encodeComponent(q)}.json',
        {'autocomplete': 'true', 'limit': '6', 'fuzzyMatch': 'true'});
    return found;
  }

  /// What's at this spot (null: nothing known, or no search).
  Future<Place?> at(double latitude, double longitude) async {
    if (!available) return null;
    final found = await _get(
        '/geocoding/${longitude.toStringAsFixed(5)},${latitude.toStringAsFixed(5)}.json',
        {'limit': '1'});
    if (found.isEmpty) return null;
    // the spot itself, named for what's there
    final place = found.first;
    return Place(
        name: place.name,
        detail: place.detail,
        latitude: latitude,
        longitude: longitude);
  }

  Future<List<Place>> _get(String path, Map<String, String> query) async {
    final uri = Uri.https('api.maptiler.com', path, {...query, 'key': _key});
    final client = _client ?? http.Client();
    try {
      final response = await client.get(uri);
      if (response.statusCode != 200) {
        throw PlaceSearchFailed(response.statusCode);
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final feature in body['features'] as List<dynamic>? ?? const [])
          if (_place(feature as Map<String, dynamic>) case final place?) place
      ];
    } finally {
      if (_client == null) client.close();
    }
  }

  /// A GeoJSON feature as a place: its own name, then where it is (the
  /// rest of its full name).
  static Place? _place(Map<String, dynamic> feature) {
    final center = feature['center'] as List<dynamic>?;
    final name = (feature['text'] as String?)?.trim();
    if (center == null || center.length < 2 || name == null || name.isEmpty) {
      return null;
    }
    final full = (feature['place_name'] as String?)?.trim() ?? '';
    var detail = full.startsWith(name)
        ? full.substring(name.length).replaceFirst(RegExp(r'^[,\s]+'), '')
        : full;
    if (detail == name) detail = '';
    return Place(
        name: name,
        detail: detail.isEmpty ? null : detail,
        latitude: (center[1] as num).toDouble(),
        longitude: (center[0] as num).toDouble());
  }
}

class PlaceSearchFailed implements Exception {
  const PlaceSearchFailed(this.status);
  final int status;

  @override
  String toString() => 'PlaceSearchFailed($status)';
}
