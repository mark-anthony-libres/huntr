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

/// Finding places for Roam, as you type, and the name of a spot picked on
/// the map: MapTiler's place search (the same key as the map's tiles); with
/// no key, or once MapTiler refuses it (for the rest of the session),
/// Photon's (OpenStreetMap's places, free, no key).
class PlaceSearch {
  PlaceSearch({String? key, http.Client? client})
      : _key = key ?? MapTiles.mapTilerKey,
        _client = client;

  final String _key;
  final http.Client? _client;

  /// MapTiler refused the key (this session): Photon from then on.
  static bool _mapTilerRefused = false;

  bool get _useMapTiler => _key.isNotEmpty && !_mapTilerRefused;

  /// There's always a search (Photon needs no key).
  bool get available => true;

  /// Places matching what's typed (2 letters or more), best first.
  Future<List<Place>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    if (_useMapTiler) {
      try {
        return await _get('/geocoding/${Uri.encodeComponent(q)}.json',
            {'autocomplete': 'true', 'limit': '6', 'fuzzyMatch': 'true'});
      } on PlaceSearchFailed catch (error) {
        if (!error.refused) rethrow;
        _mapTilerRefused = true;
      }
    }
    return _photon('/api/', {'q': q, 'limit': '8', 'lang': 'en'});
  }

  /// What's at this spot (null: nothing known).
  Future<Place?> at(double latitude, double longitude) async {
    if (!_useMapTiler) return _photonAt(latitude, longitude);
    final List<Place> found;
    try {
      found = await _get(
          '/geocoding/${longitude.toStringAsFixed(5)},${latitude.toStringAsFixed(5)}.json',
          {'limit': '1'});
    } on PlaceSearchFailed catch (error) {
      if (!error.refused) rethrow;
      _mapTilerRefused = true;
      return _photonAt(latitude, longitude);
    }
    if (found.isEmpty) return null;
    // the spot itself, named for what's there
    final place = found.first;
    return Place(
        name: place.name,
        detail: place.detail,
        latitude: latitude,
        longitude: longitude);
  }

  Future<List<Place>> _get(String path, Map<String, String> query) => _fetch(
      Uri.https('api.maptiler.com', path, {...query, 'key': _key}), _place);

  // ---- Photon (photon.komoot.io) ----

  Future<List<Place>> _photon(String path, Map<String, String> query) async {
    final found =
        await _fetch(Uri.https('photon.komoot.io', path, query), _photonPlace);
    // the same place more than once (a district and its station...): once
    final seen = <String>{};
    return [
      for (final place in found)
        if (seen.add('${place.name}|${place.detail}')) place
    ].take(6).toList();
  }

  /// The area at a spot (its neighbourhood or town, not the street).
  Future<Place?> _photonAt(double latitude, double longitude) async {
    final found = await _fetch(
        Uri.https('photon.komoot.io', '/reverse', {
          'lat': latitude.toStringAsFixed(5),
          'lon': longitude.toStringAsFixed(5),
          'lang': 'en',
        }),
        (feature) => _photonPlace(feature, area: true));
    if (found.isEmpty) return null;
    return Place(
        name: found.first.name,
        detail: found.first.detail,
        latitude: latitude,
        longitude: longitude);
  }

  /// A Photon feature as a place: its name (with [area], the area it's in:
  /// a street is named for its neighbourhood or town), then its town,
  /// region and country.
  static Place? _photonPlace(Map<String, dynamic> feature,
      {bool area = false}) {
    final p = feature['properties'] as Map<String, dynamic>? ?? const {};
    final coordinates =
        (feature['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?;
    String? text(String key) {
      final v = p[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final name = area
        ? text('locality') ??
            text('district') ??
            text('city') ??
            text('county') ??
            text('name')
        : text('name') ?? text('city');
    if (name == null || coordinates == null || coordinates.length < 2) {
      return null;
    }
    final detail = <String>[];
    for (final part in [text('city'), text('state'), text('country')]) {
      if (part != null && part != name && !detail.contains(part)) {
        detail.add(part);
      }
    }
    return Place(
        name: name,
        detail: detail.isEmpty ? null : detail.join(', '),
        latitude: (coordinates[1] as num).toDouble(),
        longitude: (coordinates[0] as num).toDouble());
  }

  Future<List<Place>> _fetch(
      Uri uri, Place? Function(Map<String, dynamic>) read) async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(uri);
      if (response.statusCode != 200) {
        throw PlaceSearchFailed(response.statusCode);
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final feature in body['features'] as List<dynamic>? ?? const [])
          if (read(feature as Map<String, dynamic>) case final place?) place
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

  /// The key isn't accepted (wrong, disabled, limited to other sites).
  bool get refused => status == 401 || status == 403;

  @override
  String toString() => 'PlaceSearchFailed($status)';
}
