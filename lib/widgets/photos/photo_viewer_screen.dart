import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'cached_photo_image.dart';
import 'viewer_controls.dart';

/// Runs one action on a photo; true when it worked.
typedef PhotoAction = Future<bool> Function(ProfilePhoto photo);

/// Crops a photo; the saved crop is a new photo (new id), or null when
/// nothing was saved.
typedef PhotoEditAction = Future<ProfilePhoto?> Function(ProfilePhoto photo);

/// Full-screen viewer for my photos: swipe left/right between them, with
/// Set as default, Edit / Crop and Remove for the one on screen. It follows
/// the photo list in [AppState], so changes show up right away.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.initialPhotoId,
    required this.onSetDefault,
    required this.onEdit,
    required this.onRemove,
  });

  final int initialPhotoId;
  final PhotoAction onSetDefault;
  final PhotoEditAction onEdit;
  final PhotoAction onRemove;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

enum _Action { setDefault, edit, remove }

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  PageController? _pages;

  /// The photo on screen, by id, so the right one stays shown when the list
  /// is reordered (e.g. a new default moves to the front).
  late int _currentId = widget.initialPhotoId;
  _Action? _running;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  int _indexOf(List<ProfilePhoto> photos, int id) {
    final index = photos.indexWhere((photo) => photo.id == id);
    return index < 0 ? 0 : index;
  }

  void _goTo(int index) => _pages?.animateToPage(index,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  Future<void> _run(_Action action, PhotoAction run, ProfilePhoto photo) async {
    setState(() => _running = action);
    final photosBefore = AppScope.read(context).profilePhotos;
    final done = await run(photo);
    if (!mounted) return;
    setState(() => _running = null);
    if (!done || action != _Action.remove) return;

    // Removed: show the neighbour, or close when nothing is left.
    final photos = AppScope.read(context).profilePhotos;
    if (photos.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final oldIndex = _indexOf(photosBefore, photo.id);
    final next = photos[oldIndex.clamp(0, photos.length - 1)];
    setState(() => _currentId = next.id);
    _pages?.jumpToPage(_indexOf(photos, next.id));
  }

  /// Cropped: the crop replaced the photo under a new id, so follow it.
  Future<void> _edit(ProfilePhoto photo) => _run(_Action.edit, (photo) async {
        final saved = await widget.onEdit(photo);
        if (saved == null || !mounted) return false;
        final photos = AppScope.read(context).profilePhotos;
        setState(() => _currentId = saved.id);
        _pages?.jumpToPage(_indexOf(photos, saved.id));
        return true;
      }, photo);

  Future<void> _confirmRemove(ProfilePhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
            key: const Key('photoRemoveConfirm'),
            style: TextButton.styleFrom(foregroundColor: HuntrColors.coral),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(_Action.remove, widget.onRemove, photo);
  }

  @override
  Widget build(BuildContext context) {
    final photos = AppScope.of(context).profilePhotos;
    if (photos.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final index = _indexOf(photos, _currentId);
    _pages ??= PageController(initialPage: index);
    final photo = photos[index];
    final busy = _running != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // the photos, edge to edge
        SwipeAnyDevice(
            child: PageView.builder(
          key: const Key('photoViewerPages'),
          controller: _pages,
          itemCount: photos.length,
          physics: busy ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (page) => setState(() => _currentId = photos[page].id),
          itemBuilder: (_, page) => InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: AspectRatio(
                aspectRatio: photos[page].width / photos[page].height,
                child: CachedPhotoImage(photos[page], fit: BoxFit.contain),
              ),
            ),
          ),
        )),

        // top bar: Main badge, position, close
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: photo.isDefault
                      ? Container(
                          key: const Key('photoViewerMain'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: HuntrColors.accentGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Main',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700)),
                        )
                      : null,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${index + 1} / ${photos.length}',
                    key: const Key('photoViewerPosition'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  child: IconButton(
                    tooltip: 'Close',
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ]),
          ),
        ),

        // previous / next arrows for mouse users
        if (photos.length > 1) ...[
          if (index > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: ArrowButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Previous photo',
                  onPressed: busy ? null : () => _goTo(index - 1)),
            ),
          if (index < photos.length - 1)
            Align(
              alignment: Alignment.centerRight,
              child: ArrowButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Next photo',
                  onPressed: busy ? null : () => _goTo(index + 1)),
            ),
        ],

        // actions for the photo on screen
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xE6000000)],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (photos.length > 1) ...[
                    PageDots(count: photos.length, current: index),
                    const SizedBox(height: 18),
                  ],
                  _ActionBar(
                    children: [
                      _ActionButton(
                        key: const Key('photoSetDefault'),
                        icon: photo.isDefault
                            ? Icons.check_circle
                            : Icons.star_outline,
                        label: photo.isDefault
                            ? 'Default photo'
                            : 'Set as default',
                        running: _running == _Action.setDefault,
                        onPressed: busy || photo.isDefault
                            ? null
                            : () => _run(
                                _Action.setDefault, widget.onSetDefault, photo),
                      ),
                      _ActionButton(
                        key: const Key('photoEdit'),
                        icon: Icons.crop,
                        label: 'Edit / Crop',
                        running: _running == _Action.edit,
                        onPressed: busy ? null : () => _edit(photo),
                      ),
                      _ActionButton(
                        key: const Key('photoRemove'),
                        icon: Icons.delete_outline,
                        label: 'Remove',
                        danger: true,
                        running: _running == _Action.remove,
                        onPressed: busy ? null : () => _confirmRemove(photo),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The rounded panel holding the actions, side by side with dividers.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                  width: 1,
                  indent: 12,
                  endIndent: 12,
                  color: Colors.white.withValues(alpha: 0.12)),
            Expanded(child: children[i]),
          ],
        ]),
      ),
    );
  }
}

/// One action: a tinted round icon with its label underneath.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.running,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool running;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? HuntrColors.coral : HuntrColors.orange;
    // Disabled actions fade, except while they run (they show a spinner).
    final faded = onPressed == null && !running;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: faded ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: running
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: color))
                    : Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}
