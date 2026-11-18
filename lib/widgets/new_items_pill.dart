import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'page_title.dart' show TabShown;

/// "↑ (faces) posted" at the top of a list, like X's: there's something
/// newer than the list shows (new threads, people who arrived nearby).
/// Tapped, the list goes to the top and shows them.
class NewItemsPill extends StatelessWidget {
  const NewItemsPill({
    super.key,
    required this.faces,
    required this.label,
    required this.visible,
    required this.onTap,
  });

  /// Who it's about (up to [maxFaces] are shown, overlapping).
  final List<Widget> faces;
  final String label;

  /// Sliding in (true) or out.
  final bool visible;
  final VoidCallback onTap;

  static const maxFaces = 3;
  static const _face = 26.0;
  static const _overlap = 9.0;

  @override
  Widget build(BuildContext context) {
    final shown = faces.take(maxFaces).toList();
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1.4),
        duration: const Duration(milliseconds: 260),
        curve: visible ? Curves.easeOutBack : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Semantics(
            button: true,
            label: 'Show new: $label',
            child: Material(
              key: const Key('newItemsPill'),
              color: HuntrColors.orange,
              shape: const StadiumBorder(),
              // no shadow: it would show as a dark ring on the dark app
              elevation: 0,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 5, 16, 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_upward_rounded,
                        color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                    // the faces, each a little over the one before
                    SizedBox(
                      width: shown.isEmpty
                          ? 0
                          : _face + (shown.length - 1) * (_face - _overlap),
                      height: _face,
                      child: Stack(children: [
                        for (final (i, face) in shown.indexed)
                          Positioned(
                            left: i * (_face - _overlap),
                            child: Container(
                              width: _face,
                              height: _face,
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                  color: HuntrColors.orange,
                                  shape: BoxShape.circle),
                              child: ClipOval(child: face),
                            ),
                          ),
                      ]),
                    ),
                    if (shown.isNotEmpty) const SizedBox(width: 8),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs [check] every [every] while [context]'s tab is the one shown and
/// the app is in front (not while it's in the background or another tab is
/// open).
class NewItemsWatch {
  NewItemsWatch(
      {required this.context, required this.every, required this.check});

  final BuildContext context;
  final Duration every;
  final Future<void> Function() check;

  Timer? _timer;
  bool _checking = false;

  void start() {
    _timer ??= Timer.periodic(every, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_checking || !context.mounted) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (!TabShown.isShown(context)) return;
    _checking = true;
    try {
      await check();
    } catch (error) {
      debugPrint('New items not checked: $error');
    } finally {
      _checking = false;
    }
  }
}
