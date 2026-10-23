import 'package:flutter/material.dart';

import '../../flows/my_albums.dart';
import '../../screens/my_album_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/photo_cache/photo_cache.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'profile_photo_grid.dart';
import 'section_states.dart';
import 'settings_group.dart';

/// "My albums" on Me: up to the backend's limit of private albums (sample
/// albums kept on this device when there is no backend).
class MyAlbumsSection extends StatefulWidget {
  const MyAlbumsSection({super.key});

  @override
  State<MyAlbumsSection> createState() => _MyAlbumsSectionState();
}

class _MyAlbumsSectionState extends State<MyAlbumsSection> {
  static const _captionStyle =
      TextStyle(color: HuntrColors.muted, fontSize: 14, height: 1.4);

  bool _started = false;
  bool _loading = false;
  String? _loadError;

  bool get _onBackend => ServicesScope.albumsOf(context) != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !_onBackend) return;
    _started = true;
    ServicesScope.photoCacheOf(context, PhotoCollection.album)?.refresh =
        (itemId) => MyAlbums.of(context).refresh(itemId);
    _load();
  }

  Future<void> _load() async {
    final token = AppScope.read(context).sessionToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await MyAlbums.of(context).load(token);
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newAlbum() async {
    final name = await promptAlbumName(context);
    if (name == null || !mounted) return;
    final album = _onBackend
        ? await MyAlbums.of(context).create(name.trim())
        : AppScope.read(context).createAlbum(name);
    if (album == null || !mounted) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MyAlbumScreen(albumId: album.id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final limits = app.albumLimits;
    final full = limits != null && app.myAlbums.length >= limits.maxAlbums;
    final waiting = _onBackend && limits == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          limits != null
              ? 'MY ALBUMS · ${app.myAlbums.length}/${limits.maxAlbums}'
              // not loaded from the backend (yet): no count to show
              : waiting
                  ? 'MY ALBUMS'
                  : 'MY ALBUMS · ${app.myAlbums.length}',
          trailing: TextButton.icon(
            key: const Key('newAlbum'),
            style: TextButton.styleFrom(
              foregroundColor: HuntrColors.orange,
              textStyle: const TextStyle(
                  fontFamily: huntrFontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            icon: const Icon(Icons.add, size: 22),
            label: const Text('New album'),
            onPressed: full || waiting ? null : _newAlbum,
          ),
        ),
        const Text(
          'Private and separate from your profile. You choose one to send when you send or accept a chat request.',
          style: _captionStyle,
        ),
        const SizedBox(height: 14),
        if (waiting && _loadError != null)
          LoadFailedCard(
            title: "Couldn't load your albums",
            message: _loadError!,
            onRetry: _load,
            retryKey: const Key('albumsRetry'),
          )
        else if (waiting || _loading && app.myAlbums.isEmpty)
          const LoadingRows()
        else if (app.myAlbums.isEmpty)
          EmptyStateCard(
            icon: Icons.photo_library_outlined,
            title: 'No albums yet',
            message: 'Create an album of private photos and videos to share '
                'when you send or accept a chat request.',
            actionLabel: 'Create album',
            onAction: _newAlbum,
            actionKey: const Key('createFirstAlbum'),
          ),
        for (final album in app.myAlbums)
          AlbumCard(
            album: album,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MyAlbumScreen(albumId: album.id))),
          ),
        if (full)
          LimitNotice(
              key: const Key('albumLimitReached'),
              message: "You've reached the maximum of ${limits.maxAlbums} "
                  'albums. Delete one to create another.'),
      ],
    );
  }
}
