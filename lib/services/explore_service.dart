import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show MapArea, NearbyPage;
import '../models/models.dart';

/// People nearby, from the backend.
class ExploreService {
  const ExploreService();

  /// Explore's map: the people in this area (blurred positions).
  Future<MapArea> fetchMapArea(String token,
          {required double south,
          required double west,
          required double north,
          required double east}) async =>
      backend.fetchMapArea(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          south: south,
          west: west,
          north: north,
          east: east);

  /// The stories tray: people nearby with a story, a page at a time.
  Future<NearbyPage> fetchStoryPeople(String token, {int offset = 0}) async =>
      backend.fetchStoryPeople(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          offset: offset);

  Future<NearbyPage> fetchNearby(String token,
          {int offset = 0, bool newest = false}) async =>
      backend.fetchNearby(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          offset: offset,
          newest: newest);

  /// One person with all their photos.
  Future<Profile> fetchPerson(String token, int userId) async =>
      backend.fetchPerson(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          userId: userId);
}
