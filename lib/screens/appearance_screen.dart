import 'package:flutter/material.dart';

import '../models/models.dart' show ExploreLayout;
import '../services/app_icon.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/me/settings_group.dart';

/// Settings > Appearance: the app's theme (its accent colour, everywhere,
/// remembered on this device), and on the Android app, the home-screen icon
/// and name.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  /// The icon on the home screen now (null: not known yet, or not Android).
  String? _icon;

  @override
  void initState() {
    super.initState();
    if (AppIcons.supported) _loadIcon();
  }

  Future<void> _loadIcon() async {
    try {
      final icon = await AppIcons.current();
      if (mounted) setState(() => _icon = icon);
    } catch (error) {
      debugPrint('App icon not read: $error');
    }
  }

  Future<void> _useIcon(AppIconChoice choice) async {
    if (choice.id == _icon) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppIcons.use(choice.id);
      if (mounted) setState(() => _icon = choice.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(choice.discreet
                ? 'HUNTR now shows as "${choice.label}" on your home screen.'
                : 'Your home screen icon changed.')));
    } catch (error) {
      debugPrint('App icon not changed: $error');
      messenger.showSnackBar(const SnackBar(
          content: Text("The icon couldn't be changed. Please try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: const Key('appearanceList'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // ---- theme ----
              const SectionLabel('THEME'),
              const SizedBox(height: 4),
              const Text('The colour of the whole app, on this device.',
                  style: TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 12),
              ValueListenableBuilder<HuntrPalette>(
                valueListenable: app.appearance,
                builder: (context, chosen, _) => LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth >= 520 ? 3 : 2;
                    const gap = 10.0;
                    final width =
                        (box.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(spacing: gap, runSpacing: gap, children: [
                      for (final palette in huntrPalettes)
                        SizedBox(
                          width: width,
                          child: _ThemeCard(
                            palette: palette,
                            chosen: palette.id == chosen.id,
                            onTap: () => app.usePalette(palette),
                          ),
                        ),
                    ]);
                  },
                ),
              ),

              // ---- Explore grid ----
              const SizedBox(height: 28),
              const SectionLabel('EXPLORE GRID'),
              const SizedBox(height: 4),
              const Text(
                  'How many people Explore shows across, on this device.',
                  style: TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 12),
              for (final layout in ExploreLayout.values)
                _LayoutOption(
                  layout: layout,
                  chosen: layout == app.exploreLayout,
                  onTap: () => app.exploreLayout = layout,
                ),

              // ---- app icon (the Android app) ----
              if (AppIcons.supported) ...[
                const SizedBox(height: 28),
                const SectionLabel('APP ICON'),
                const SizedBox(height: 4),
                const Text(
                    'How HUNTR looks on your home screen. Notes, Weather and '
                    'Clock look like plain apps, with those names, for '
                    'privacy. Your phone may take a moment to show it, and '
                    'may close HUNTR once when it changes.',
                    style: TextStyle(color: HuntrColors.muted, height: 1.4)),
                const SizedBox(height: 14),
                Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final choice in appIconChoices)
                    _IconTile(
                      choice: choice,
                      chosen: choice.id == _icon,
                      onTap: () => _useIcon(choice),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One Explore layout: how many across, what the cards show, and a little
/// picture of it; the one in use is in orange with a tick.
class _LayoutOption extends StatelessWidget {
  const _LayoutOption(
      {required this.layout, required this.chosen, required this.onTap});

  final ExploreLayout layout;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: chosen
            ? HuntrColors.orange.withValues(alpha: 0.10)
            : HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: chosen
                  ? HuntrColors.orange
                  : Colors.white.withValues(alpha: 0.08),
              width: chosen ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('exploreLayout-${layout.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              _LayoutPicture(columns: layout.columns, chosen: chosen),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${layout.columns} across · ${layout.label}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(layout.description,
                          style: const TextStyle(
                              color: HuntrColors.muted, fontSize: 13)),
                    ]),
              ),
              if (chosen)
                Icon(Icons.check_circle_rounded,
                    key: Key('exploreLayoutChosen-${layout.name}'),
                    color: HuntrColors.orange),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A tiny grid of [columns] across, two rows deep.
class _LayoutPicture extends StatelessWidget {
  const _LayoutPicture({required this.columns, required this.chosen});

  final int columns;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final color =
        chosen ? HuntrColors.orange : Colors.white.withValues(alpha: 0.35);
    return SizedBox(
      width: 44,
      height: 44,
      child: Column(children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 3),
          Expanded(
            // the squares fill the row's height
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 3),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// One theme: its colours as a small preview, and its name; the one in use
/// has a tick.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard(
      {required this.palette, required this.chosen, required this.onTap});

  final HuntrPalette palette;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      label: '${palette.name} theme',
      child: Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('theme-${palette.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // a little of what it looks like: a button, a bubble
              Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                      colors: palette.glow,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [palette.accent, palette.ember]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text(palette.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (chosen)
                  Icon(Icons.check_rounded,
                      key: Key('themeChosen-${palette.id}'),
                      size: 20,
                      color: Colors.white),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One icon as the home screen would show it, with its name under it; the
/// one in use has a tick.
class _IconTile extends StatelessWidget {
  const _IconTile(
      {required this.choice, required this.chosen, required this.onTap});

  final AppIconChoice choice;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('appIcon-${choice.id}'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              // the launcher's own picture; a thin edge so a dark one
              // still shows on the dark page
              child: Container(
                width: 60,
                height: 60,
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: HuntrColors.border),
                ),
                child: Image.asset(choice.asset, fit: BoxFit.cover),
              ),
            ),
            if (chosen)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  key: Key('appIconChosen-${choice.id}'),
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white),
                  child: const Icon(Icons.check_rounded,
                      size: 14, color: Colors.black),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(choice.label,
              style: const TextStyle(fontSize: 12, color: HuntrColors.muted)),
        ]),
      ),
    );
  }
}
