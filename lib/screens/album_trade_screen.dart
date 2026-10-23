import 'package:flutter/material.dart';

import '../flows/my_albums.dart';
import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/me/profile_photo_grid.dart' show AlbumCard;
import '../widgets/me/section_states.dart';
import 'my_album_screen.dart';

/// Choosing one of my albums for a trade, full screen: to offer it, or to
/// answer an offer. My albums come from the backend each time.
///
/// - No albums: "Create an Album First". Creating one opens the usual album
///   screen (to add photos and videos); coming back lands here again, with
///   the list refreshed, in the same trade.
/// - One album: it's chosen at once (no list).
/// - More: a list to choose from.
///
/// [onChosen] sends the choice and throws what the backend says; the screen
/// closes (returning true) once it succeeds, and offers a retry if not.
class AlbumTradeScreen extends StatefulWidget {
  const AlbumTradeScreen({
    super.key,
    required this.title,
    required this.intro,
    required this.sendingLabel,
    required this.onChosen,
  });

  final String title;

  /// What's being chosen, e.g. "Choose an album to offer Sam."
  final String intro;

  /// While sending, e.g. 'Offering'.
  final String sendingLabel;
  final Future<void> Function(Album album) onChosen;

  @override
  State<AlbumTradeScreen> createState() => _AlbumTradeScreenState();
}

class _AlbumTradeScreenState extends State<AlbumTradeScreen> {
  List<Album>? _albums;
  String? _loadError;

  /// The album being sent, and why sending it failed.
  Album? _sending;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// My albums from the backend; one album is chosen at once.
  Future<void> _load() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null) return;
    setState(() {
      _albums = null;
      _loadError = null;
    });
    try {
      await MyAlbums.of(context).load(token);
    } on SessionRejectedException {
      if (mounted) app.endSession();
      return;
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
      return;
    }
    if (!mounted) return;
    final albums = List<Album>.of(app.myAlbums);
    setState(() => _albums = albums);
    if (albums.length == 1) await _choose(albums.single);
  }

  Future<void> _choose(Album album) async {
    if (_sending != null && _sendError == null) return; // already sending
    setState(() {
      _sending = album;
      _sendError = null;
    });
    try {
      await widget.onChosen(album);
      if (mounted) Navigator.of(context).pop(true);
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _sendError = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    }
  }

  /// The usual album creation (name, then the album screen to add photos
  /// and videos); then back here, refreshed.
  Future<void> _createAlbum() async {
    final name = await promptAlbumName(context);
    if (name == null || !mounted) return;
    final album = await MyAlbums.of(context).create(name.trim());
    if (album == null || !mounted) return; // the error was shown; try again
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MyAlbumScreen(albumId: album.id)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final sending = _sending;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          key: const Key('closeTrade'),
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _loadError != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: LoadFailedCard(
                        title: "Couldn't load your albums",
                        message: _loadError!,
                        onRetry: _load,
                        retryKey: const Key('tradeAlbumsRetry'),
                      ),
                    ),
                  )
                : albums == null
                    ? const Center(child: CircularProgressIndicator())
                    : sending != null &&
                            (albums.length == 1 || _sendError == null)
                        ? _Sending(
                            album: sending,
                            label: widget.sendingLabel,
                            error: _sendError,
                            onRetry: () => _choose(sending),
                            onBack: () => Navigator.of(context).pop(false),
                          )
                        : albums.isEmpty
                            ? _NoAlbums(onCreate: _createAlbum)
                            : _AlbumList(
                                intro: widget.intro,
                                albums: albums,
                                error: _sendError,
                                onChoose: _choose,
                              ),
          ),
        ),
      ),
    );
  }
}

/// Nothing to offer yet: create an album first.
class _NoAlbums extends StatelessWidget {
  const _NoAlbums({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('noAlbumsForTrade'),
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HuntrColors.orange.withValues(alpha: 0.12),
            border:
                Border.all(color: HuntrColors.orange.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.photo_library_outlined,
              size: 44, color: HuntrColors.orange),
        ),
        const SizedBox(height: 24),
        Text('Create an Album First',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Text(
          'To trade, you offer one of your private albums. Create one and '
          'add a few photos or videos — you’ll come right back here to '
          'finish the trade.',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: HuntrColors.muted, fontSize: 16, height: 1.45),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: const BoxDecoration(
                gradient: HuntrColors.accentGradient,
                borderRadius: BorderRadius.all(Radius.circular(30))),
            child: FilledButton.icon(
              key: const Key('createAlbumForTrade'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(54)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Album'),
              onPressed: onCreate,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Several albums: choose one.
class _AlbumList extends StatelessWidget {
  const _AlbumList({
    required this.intro,
    required this.albums,
    required this.error,
    required this.onChoose,
  });

  final String intro;
  final List<Album> albums;
  final String? error;
  final void Function(Album album) onChoose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('tradeAlbumList'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(intro,
            style: const TextStyle(
                color: HuntrColors.muted, fontSize: 15, height: 1.4)),
        const SizedBox(height: 6),
        const Text(
          'Only the album’s name and cover show in the chat. Nothing is shared.',
          style: TextStyle(color: HuntrColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ErrorLine(message: error!),
          ),
        for (final album in albums)
          AlbumCard(
            key: Key('tradeAlbum-${album.id}'),
            album: album,
            onTap: () => onChoose(album),
          ),
      ],
    );
  }
}

/// Sending the choice (or why it failed, with a retry).
class _Sending extends StatelessWidget {
  const _Sending({
    required this.album,
    required this.label,
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Album album;
  final String label;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AlbumCard(album: album, onTap: () {}),
        const SizedBox(height: 20),
        if (error == null) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('$label “${album.name}”…',
              style: const TextStyle(color: HuntrColors.muted)),
        ] else ...[
          _ErrorLine(message: error!),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 50),
                    shape: const StadiumBorder()),
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('retryTrade'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 50),
                    shape: const StadiumBorder()),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HuntrColors.coral.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuntrColors.coral.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: HuntrColors.coral),
        const SizedBox(width: 10),
        Expanded(child: Text(message, key: const Key('tradeError'))),
      ]),
    );
  }
}
