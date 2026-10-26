import 'package:flutter/material.dart';

import '../flows/my_albums.dart';
import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/me/profile_photo_grid.dart' show AlbumCard;
import '../widgets/photo.dart';
import '../widgets/me/section_states.dart';
import 'my_album_screen.dart';

/// Choosing one of my albums for a trade, full screen: to offer it, or to
/// answer an offer. My albums come from the backend each time.
///
/// - No albums: "Create an Album First". Creating one opens the usual album
///   screen (to add photos and videos); coming back lands here again, with
///   the list refreshed, in the same trade (nothing is sent yet).
/// - Only empty albums: "Add Photos First", which opens one of them (an
///   empty album can't be traded; the backend refuses it too).
/// - Otherwise a list of the albums with something in them, even of one:
///   nothing is sent until it's chosen.
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
    this.waiting = const {},
    this.onStopWaiting,
  });

  /// Albums that can't be chosen now, by id (already offered here and still
  /// waiting for an answer).
  final Set<String> waiting;

  /// Withdraws a waiting album's offer (throws what the backend says).
  /// Given: tapping a waiting album offers to stop sharing it (it can't be
  /// sent again while waiting).
  final Future<void> Function(Album album)? onStopWaiting;

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

  /// [AlbumTradeScreen.waiting], less the offers withdrawn here.
  late final Set<String> _waiting = {...widget.waiting};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// My albums from the backend.
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

  /// A waiting album: stop sharing it (withdraw the offer).
  Future<void> _waitingActions(Album album) async {
    final stop = widget.onStopWaiting;
    if (stop == null) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('“${album.name}” is offered and waiting for an answer.',
                style: const TextStyle(color: HuntrColors.muted)),
          ),
          ListTile(
            key: const Key('tradeStopSharing'),
            leading: const Icon(Icons.block_rounded, color: HuntrColors.coral),
            title: const Text('Stop sharing',
                style: TextStyle(color: HuntrColors.coral)),
            subtitle: const Text('Withdraw the offer'),
            onTap: () => Navigator.of(context).pop(true),
          ),
        ]),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sendError = null);
    try {
      await stop(album);
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
      return;
    } catch (error) {
      if (mounted) {
        setState(() => _sendError = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _waiting.remove(album.id));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stopped sharing “${album.name}”')));
  }

  /// An empty album opened to add photos and videos; then back here,
  /// refreshed.
  Future<void> _fillAlbum(Album album) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MyAlbumScreen(albumId: album.id)));
    if (mounted) await _load();
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
    // empty albums can't be traded: only the ones with something in them
    // (and one already offered here, to withdraw it)
    final albums = _albums
        ?.where((a) => a.photos.isNotEmpty || _waiting.contains(a.id))
        .toList();
    final firstEmpty = _albums?.where((a) => a.photos.isEmpty).firstOrNull;
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
                    : sending != null && _sendError == null
                        ? _Sending(album: sending, label: widget.sendingLabel)
                        : albums.isEmpty
                            ? _NoAlbums(
                                onCreate: _createAlbum,
                                emptyAlbum: firstEmpty,
                                onFill: firstEmpty == null
                                    ? null
                                    : () => _fillAlbum(firstEmpty))
                            : _AlbumList(
                                intro: widget.intro,
                                albums: albums,
                                waiting: _waiting,
                                error: _sendError,
                                onChoose: _choose,
                                onWaiting: widget.onStopWaiting == null
                                    ? null
                                    : _waitingActions,
                              ),
          ),
        ),
      ),
    );
  }
}

/// Nothing to offer yet: create an album first.
class _NoAlbums extends StatelessWidget {
  const _NoAlbums({required this.onCreate, this.emptyAlbum, this.onFill});

  final VoidCallback onCreate;

  /// Albums exist but are all empty: this one to fill ([onFill]).
  final Album? emptyAlbum;
  final VoidCallback? onFill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key(
          emptyAlbum == null ? 'noAlbumsForTrade' : 'onlyEmptyAlbumsForTrade'),
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
          child: Icon(Icons.photo_library_outlined,
              size: 44, color: HuntrColors.orange),
        ),
        const SizedBox(height: 24),
        Text(emptyAlbum == null ? 'Create an Album First' : 'Add Photos First',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(
          emptyAlbum == null
              ? 'To trade, you offer one of your private albums. Create one and '
                  'add a few photos or videos — you’ll come right back here to '
                  'finish the trade.'
              : 'Your albums are empty, and an empty album can’t be traded. '
                  'Add a few photos or videos to “${emptyAlbum!.name}” — you’ll '
                  'come right back here to finish the trade.',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: HuntrColors.muted, fontSize: 16, height: 1.45),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
                gradient: HuntrColors.accentGradient,
                borderRadius: BorderRadius.all(Radius.circular(30))),
            child: FilledButton.icon(
              key: const Key('createAlbumForTrade'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(54)),
              icon: Icon(emptyAlbum == null
                  ? Icons.add_rounded
                  : Icons.add_photo_alternate_outlined),
              label: Text(emptyAlbum == null ? 'Create Album' : 'Add Photos'),
              onPressed: emptyAlbum == null ? onCreate : onFill,
            ),
          ),
        ),
        if (emptyAlbum != null) ...[
          const SizedBox(height: 10),
          TextButton(
            key: const Key('createAnotherAlbumForTrade'),
            onPressed: onCreate,
            child: const Text('Create a new album instead'),
          ),
        ],
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
    this.waiting = const {},
    this.onWaiting,
  });

  final String intro;
  final List<Album> albums;
  final Set<String> waiting;
  final String? error;
  final void Function(Album album) onChoose;

  /// A waiting album tapped (null: it can't be).
  final void Function(Album album)? onWaiting;

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
          if (waiting.contains(album.id))
            // already offered and waiting: not to choose, but its offer can
            // be withdrawn
            _WaitingAlbumCard(
                key: Key('tradeAlbumWaiting-${album.id}'),
                album: album,
                onStop: onWaiting == null ? null : () => onWaiting!(album))
          else
            AlbumCard(
              key: Key('tradeAlbum-${album.id}'),
              album: album,
              onTap: () => onChoose(album),
            ),
      ],
    );
  }
}

/// An album already offered here and still waiting for an answer: like
/// the others, with Stop sharing in place of the arrow (it can't be offered
/// again meanwhile).
class _WaitingAlbumCard extends StatelessWidget {
  const _WaitingAlbumCard({
    super.key,
    required this.album,
    required this.onStop,
  });

  final Album album;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('tradeAlbum-${album.id}'),
          onTap: onStop,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              SizedBox(
                width: 60,
                height: 60,
                child: album.photos.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: HuntrColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.photo_library_outlined,
                            color: HuntrColors.muted),
                      )
                    : PhotoArt(
                        photo: album.photos.first, radius: 10, iconSize: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${album.contentsLabel} · Private',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: HuntrColors.muted)),
                  ],
                ),
              ),
              if (onStop != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: Key('stopSharing-${album.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HuntrColors.coral,
                    side: BorderSide(
                        color: HuntrColors.coral.withValues(alpha: 0.6)),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    visualDensity: VisualDensity.compact,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: onStop,
                  child: const Text('Stop sharing',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sending the choice (a failure shows in the list, to choose again).
class _Sending extends StatelessWidget {
  const _Sending({required this.album, required this.label});

  final Album album;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AlbumCard(album: album, onTap: () {}),
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('$label “${album.name}”…',
            style: const TextStyle(color: HuntrColors.muted)),
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
