import 'package:flutter/material.dart';

import '../theme.dart';

/// The app's root, following the chosen theme: when [appearance] changes,
/// the app is built again with it - the MaterialApp's theme, and every
/// screen already open (their colours are read while building, from
/// [HuntrColors]), so the whole app turns at once without leaving them.
class ThemeFollower extends StatefulWidget {
  const ThemeFollower(
      {super.key, required this.appearance, required this.builder});

  final ValueNotifier<HuntrPalette> appearance;
  final WidgetBuilder builder;

  @override
  State<ThemeFollower> createState() => _ThemeFollowerState();
}

class _ThemeFollowerState extends State<ThemeFollower> {
  @override
  void initState() {
    super.initState();
    widget.appearance.addListener(_changed);
  }

  @override
  void dispose() {
    widget.appearance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // screens on the navigator (and anything const-free that didn't
    // rebuild) read the new colours too
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
