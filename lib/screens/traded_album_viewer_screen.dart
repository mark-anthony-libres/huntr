import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';
import '../widgets/photos/viewer_controls.dart';

/// The other person's album of a completed trade, opened. Like chat media:
/// a viewing session serves it only while it's open (heartbeats keep it),
/// my countdown is paused while I view (nothing closes or stops here), and
/// leaving ends the session - the countdown then starts - and drops what
/// it showed. Nothing is saved on the device.
class TradedAlbumViewerScreen extends StatefulWidget {
  const TradedAlbumViewerScreen({super.key, required this.message});

  final ChatMessage message;

  @override
  State<TradedAlbumViewerScreen> createState() =>
      _TradedAlbumViewerScreenState();
}

class _TradedAlbumViewerScreenState extends State<TradedAlbumViewerScreen> {
  TradedAlbumAccess? _access;
  String? _error;
  bool _expired = false;
  int _index = 0;
  final PageController _pages = PageController();
  Timer? _heartbeat;
  MessagingState? _messaging;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final messaging = _messaging = MessagingScope.read(context)!;
    setState(() {
      _error = null;
      _expired = false;
    });
    try {
      final access = await messaging.viewTradedAlbum(widget.message);
      if (!mounted || access == null) return;
      setState(() => _access = access);
      _heartbeat = Timer.periodic(
          access.view.heartbeat, (_) => messaging.viewHeartbeat(access.view));
    } on MediaExpiredException catch (error) {
      if (mounted) {
        setState(() {
          _expired = true;
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    }
  }

  /// Leaving: ends the session (my countdown starts) and drops the photos
  /// from memory.
  void _forget() {
    _heartbeat?.cancel();
    final access = _access;
    if (access != null) {
      unawaited(_messaging?.endView(access.view, widget.message));
    }
    for (final item in access?.items ?? const <StoredAlbumItem>[]) {
      unawaited(NetworkImage(item.imageUrl).evict());
    }
    _access = null;
  }

  @override
  void dispose() {
    _forget();
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) => _pages.animateToPage(index,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final items = access?.items ?? const <StoredAlbumItem>[];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(access == null
            ? 'Their album'
            : items.isEmpty
                ? '“${access.name}”'
                : '“${access.name}” · ${_index + 1} of ${items.length}'),
        actions: [
          if (access != null && access.view.countdownPaused)
            const _PausedNote(),
        ],
      ),
      body: SafeArea(
        child: _expired
            ? _Note(
                key: const Key('albumExpired'),
                icon: Icons.timer_off_outlined,
                text: _error ?? 'This album has expired.')
            : _error != null
                ? _Note(
                    icon: Icons.error_outline_rounded,
                    text: _error!,
                    action: TextButton(
                        onPressed: _open, child: const Text('Try again')))
                : access == null
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? const _Note(
                            icon: Icons.photo_library_outlined,
                            text: 'This album is empty.')
                        : Stack(children: [
                            SwipeAnyDevice(
                              child: PageView.builder(
                                key: const Key('tradedAlbumPages'),
                                controller: _pages,
                                itemCount: items.length,
                                onPageChanged: (i) =>
                                    setState(() => _index = i),
                                itemBuilder: (_, i) => Center(
                                  child: items[i].isVideo
                                      ? _Video(
                                          key: ValueKey(items[i].id),
                                          item: items[i],
                                          active: i == _index)
                                      : InteractiveViewer(
                                          child: Image.network(items[i].url,
                                              webHtmlElementStrategy:
                                                  WebHtmlElementStrategy
                                                      .fallback,
                                              errorBuilder: (context, error,
                                                      stack) =>
                                                  const _Note(
                                                      icon: Icons
                                                          .broken_image_outlined,
                                                      text:
                                                          'This photo could not be loaded.')),
                                        ),
                                ),
                              ),
                            ),
                            if (items.length > 1) ...[
                              if (_index > 0)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: ArrowButton(
                                      icon: Icons.chevron_left,
                                      tooltip: 'Previous',
                                      onPressed: () => _goTo(_index - 1)),
                                ),
                              if (_index < items.length - 1)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ArrowButton(
                                      icon: Icons.chevron_right,
                                      tooltip: 'Next',
                                      onPressed: () => _goTo(_index + 1)),
                                ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: PageDots(
                                      count: items.length, current: _index),
                                ),
                              ),
                            ],
                          ]),
      ),
    );
  }
}

/// One of their videos, streamed from its short-lived link.
class _Video extends StatefulWidget {
  const _Video({super.key, required this.item, required this.active});

  final StoredAlbumItem item;
  final bool active;

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final VideoPlayerController _player =
      VideoPlayerController.networkUrl(Uri.parse(widget.item.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_changed);
    _player.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.active) _player.play();
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_Video oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _player.pause();
  }

  @override
  void dispose() {
    _player.removeListener(_changed);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const _Note(
          icon: Icons.videocam_off_outlined,
          text: 'This video could not be played.');
    }
    if (!_player.value.isInitialized) return const CircularProgressIndicator();
    final playing = _player.value.isPlaying;
    return GestureDetector(
      onTap: () => playing ? _player.pause() : _player.play(),
      child: AspectRatio(
        aspectRatio: _player.value.aspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          VideoPlayer(_player),
          if (!playing)
            const Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    size: 72, color: Colors.white70)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: VideoProgressIndicator(_player, allowScrubbing: true),
          ),
        ]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Colors.white54),
          const SizedBox(height: 14),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ]),
      ),
    );
  }
}

/// My countdown is paused while I view.
class _PausedNote extends StatelessWidget {
  const _PausedNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 16),
      child: Center(
        child: Row(key: Key('countdownPaused'), children: [
          Icon(Icons.timer_outlined, size: 18, color: Colors.white70),
          SizedBox(width: 4),
          Text('Timer starts when you close this',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ),
    );
  }
}
