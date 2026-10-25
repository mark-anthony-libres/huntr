import 'package:flutter/material.dart';

import '../theme.dart';

/// How many times each tab has been opened (HomeShell gives every tab its
/// own count): a [PageTitle] in it plays again each time.
class PageVisits extends InheritedNotifier<ValueNotifier<int>> {
  const PageVisits(
      {super.key, required ValueNotifier<int> visits, required super.child})
      : super(notifier: visits);

  static ValueNotifier<int>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageVisits>()?.notifier;
}

/// A page's big title (like "Me"), opening with the brand: "huntr"
/// comes in letter by letter, stays a moment, then gives way to the title.
/// It plays each time the page is opened (once when it's outside a tab),
/// and not at all when the device asks for less motion.
class PageTitle extends StatefulWidget {
  const PageTitle(this.title,
      {super.key, required this.style, this.gradient = true});

  final String title;
  final TextStyle? style;

  /// The title in HUNTR's orange gradient (otherwise as [style] says).
  final bool gradient;

  @override
  State<PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<PageTitle>
    with SingleTickerProviderStateMixin {
  static const _brand = 'huntr';

  // the whole thing; the parts below are fractions of it
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2300));
  ValueNotifier<int>? _visits;
  int _played = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visits = PageVisits.of(context);
    if (visits == _visits) return;
    _visits?.removeListener(_maybePlay);
    _visits = visits?..addListener(_maybePlay);
    if (visits == null && _played == 0) {
      _play();
    } else {
      _maybePlay();
    }
  }

  /// A new visit to the page (never one that hasn't been opened yet).
  void _maybePlay() {
    final visits = _visits?.value ?? 0;
    if (visits > _played) {
      _played = visits;
      _play();
    }
  }

  void _play() {
    _played = _played == 0 ? 1 : _played;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _visits?.removeListener(_maybePlay);
    _controller.dispose();
    super.dispose();
  }

  Widget _gradient(Widget child) => ShaderMask(
      shaderCallback: HuntrColors.accentGradient.createShader, child: child);

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? const TextStyle())
        .copyWith(fontWeight: FontWeight.w800, color: Colors.white);
    final title = Text(widget.title,
        key: const Key('pageTitle'),
        style: widget.gradient ? style : widget.style);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // never started (a tab not opened yet): just the title
        if (_controller.status == AnimationStatus.dismissed || t >= 1) {
          return widget.gradient ? _gradient(title) : title;
        }
        // 0-0.45: the letters come in; 0.7-0.9: brand out, title in
        final out = Curves.easeIn.transform(((t - 0.7) / 0.2).clamp(0, 1));
        final into =
            Curves.easeOutCubic.transform(((t - 0.75) / 0.25).clamp(0, 1));
        return ClipRect(
          child: Stack(alignment: AlignmentDirectional.centerStart, children: [
            // the title, rising into place
            Opacity(
              opacity: into,
              child: Transform.translate(
                  offset: Offset(0, 14 * (1 - into)),
                  child: widget.gradient ? _gradient(title) : title),
            ),
            // the brand, letter by letter, then up and away
            if (out < 1)
              Opacity(
                opacity: 1 - out,
                child: Transform.translate(
                  offset: Offset(0, -14 * out),
                  child: _gradient(Row(
                    key: const Key('pageTitleBrand'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, letter) in _brand.split('').indexed)
                        _letter(letter, style, t, i),
                    ],
                  )),
                ),
              ),
          ]),
        );
      },
    );
  }

  /// One letter of the brand: each a little after the one before.
  Widget _letter(String letter, TextStyle style, double t, int i) {
    final start = i * 0.07;
    final shown =
        Curves.easeOutBack.transform(((t - start) / 0.17).clamp(0, 1));
    return Opacity(
      opacity: shown.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - shown)),
        child: Transform.scale(
            scale: 0.6 + 0.4 * shown, child: Text(letter, style: style)),
      ),
    );
  }
}
