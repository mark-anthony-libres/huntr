import 'package:flutter/material.dart';

import '../../theme.dart';

/// Small caps section title, with an optional widget on the right.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.info});

  final String text;
  final Widget? trailing;

  /// Right after the text (an ⓘ that explains the section).
  final Widget? info;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: HuntrColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            if (info != null) ...[const SizedBox(width: 2), info!],
          ]),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// What's typed in Settings' search box, for the [SettingsGroup]s and
/// [SettingsRow]s under it: a row stays when its title or subtext has it.
class SettingsSearch extends InheritedWidget {
  const SettingsSearch(
      {super.key,
      required this.query,
      required this.results,
      required super.child});

  /// Lowercase and trimmed; empty when nothing is typed.
  final String query;
  final SettingsSearchResults results;

  bool get active => query.isNotEmpty;

  bool matches(String text) => text.toLowerCase().contains(query);

  static SettingsSearch? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSearch>();

  @override
  bool updateShouldNotify(SettingsSearch old) => query != old.query;
}

/// Whether the search found anything: each [SettingsGroup] says, as it's
/// built, and this tells once the frame is drawn.
class SettingsSearchResults extends ChangeNotifier {
  final _found = <Element, bool>{};
  bool _any = true;
  bool _pending = false;

  bool get any => _any;

  void _report(BuildContext group, bool found) {
    _found[group as Element] = found;
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      _found.removeWhere((group, _) => !group.mounted);
      final any = _found.values.any((found) => found);
      if (any != _any) {
        _any = any;
        notifyListeners();
      }
    });
  }
}

/// One section of Settings: its [SettingsGroup] shows [label] above it (and
/// space under it), and a search hides both when none of its rows match.
/// Searching for the label itself shows the whole section.
class SettingsSection extends InheritedWidget {
  const SettingsSection({super.key, required this.label, required super.child});

  final String label;

  static String? labelOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSection>()?.label;

  @override
  bool updateShouldNotify(SettingsSection old) => label != old.label;
}

/// Rows grouped in one rounded card, separated by thin dividers. In a
/// [SettingsSection], with its label; under a [SettingsSearch], only the
/// rows that match (nothing at all when none do).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  static const _sectionGap = 28.0;

  @override
  Widget build(BuildContext context) {
    final label = SettingsSection.labelOf(context);
    final search = SettingsSearch.maybeOf(context);
    var rows = children;
    if (search != null && search.active) {
      final wholeSection = label != null && search.matches(label);
      rows = [
        for (final row in children)
          if (row is SettingsRow &&
              (wholeSection ||
                  search.matches(row.title) ||
                  search.matches(row.subtitle)))
            row,
      ];
      search.results._report(context, rows.isNotEmpty);
      if (rows.isEmpty) return const SizedBox.shrink();
    }
    final card = _card(rows);
    if (label == null) return card;
    return Padding(
      padding: const EdgeInsets.only(bottom: _sectionGap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(label),
        const SizedBox(height: 10),
        card,
      ]),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HuntrColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 64, color: HuntrColors.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row in a [SettingsGroup]: orange icon, title, subtitle, and either a
/// control (e.g. a switch) or a chevron when it opens something.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Red title and icon, for destructive actions.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? HuntrColors.coral : HuntrColors.orange;
    final search = SettingsSearch.maybeOf(context);
    final query = search != null && search.active ? search.query : '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 26),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    _highlighted(title, query),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: danger ? HuntrColors.coral : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(_highlighted(subtitle, query),
                      style: const TextStyle(
                          color: HuntrColors.muted, fontSize: 13.5)),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right, color: HuntrColors.muted),
          ],
        ),
      ),
    );
  }
}

/// [text] with each place it has [query] (lowercase) in the accent.
TextSpan _highlighted(String text, String query) {
  final lower = text.toLowerCase();
  // (a letter whose lowercase is longer would shift the places)
  if (query.isEmpty || lower.length != text.length) {
    return TextSpan(text: text);
  }
  final spans = <TextSpan>[];
  var from = 0;
  for (var at = lower.indexOf(query);
      at >= 0;
      at = lower.indexOf(query, from)) {
    if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
    spans.add(TextSpan(
        text: text.substring(at, at + query.length),
        style:
            TextStyle(color: HuntrColors.orange, fontWeight: FontWeight.w700)));
    from = at + query.length;
  }
  if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
  return TextSpan(children: spans);
}
