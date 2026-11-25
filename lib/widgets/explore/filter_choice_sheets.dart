import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../pill_chip.dart';

/// One of Explore's quick filters with several choices ("Looking for",
/// "Position"): a chip that opens a sheet of them. Several can be ticked,
/// each applied as it's tapped; Clear unticks them all, Done closes it.
class ChoicesFilterChip<T> extends StatelessWidget {
  const ChoicesFilterChip({
    super.key,
    required this.name,
    required this.title,
    required this.icon,
    required this.options,
    required this.labelOf,
    required this.chosen,
    required this.onChanged,
    this.iconOf,
    this.note,
  });

  /// For the keys: `<name>Chip`, `<name>Option-<option>`.
  final String name;

  /// The chip's label with nothing chosen, and the sheet's title.
  final String title;
  final IconData icon;
  final List<T> options;
  final String Function(T option) labelOf;

  /// Each option's icon, if they have one (the chip wears the one chosen).
  final IconData Function(T option)? iconOf;

  /// A line under the sheet's title.
  final String? note;
  final Set<T> chosen;
  final ValueChanged<Set<T>> onChanged;

  /// "Looking for", the one choice, or "Looking for (2)".
  String get _label => switch (chosen.length) {
        0 => title,
        1 => labelOf(chosen.first),
        final n => '$title ($n)',
      };

  String _keyOf(T option) => option is Enum ? option.name : '$option';

  @override
  Widget build(BuildContext context) => PillChip(
        key: Key('${name}Chip'),
        icon:
            chosen.length == 1 && iconOf != null ? iconOf!(chosen.first) : icon,
        label: _label,
        dropdown: true,
        selected: chosen.isNotEmpty,
        onSelected: (_) => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ChoicesSheet<T>(chip: this, keyOf: _keyOf),
        ),
      );
}

class _ChoicesSheet<T> extends StatefulWidget {
  const _ChoicesSheet({required this.chip, required this.keyOf});

  final ChoicesFilterChip<T> chip;
  final String Function(T option) keyOf;

  @override
  State<_ChoicesSheet<T>> createState() => _ChoicesSheetState<T>();
}

class _ChoicesSheetState<T> extends State<_ChoicesSheet<T>> {
  late Set<T> _chosen = {...widget.chip.chosen};

  void _set(Set<T> next) {
    setState(() => _chosen = next);
    widget.chip.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final chip = widget.chip;
    return _SheetFrame(
      title: chip.title,
      note: chip.note,
      onClear: _chosen.isEmpty ? null : () => _set({}),
      children: [
        for (final option in chip.options)
          _ChoiceRow(
            key: Key('${chip.name}Option-${widget.keyOf(option)}'),
            icon: chip.iconOf?.call(option),
            label: chip.labelOf(option),
            selected: _chosen.contains(option),
            onTap: () {
              final next = {..._chosen};
              next.contains(option) ? next.remove(option) : next.add(option);
              _set(next);
            },
          ),
      ],
    );
  }
}

/// A choice in a sheet: a big row, ticked when chosen.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          checked: selected,
          child: Material(
            color: selected
                ? HuntrColors.orange.withValues(alpha: 0.14)
                : HuntrColors.surfaceHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: selected ? HuntrColors.orange : Colors.transparent,
                  width: 1.4),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: 20,
                        color:
                            selected ? HuntrColors.orange : HuntrColors.muted),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: selected
                        ? Icon(Icons.check_circle_rounded,
                            key: const ValueKey('on'),
                            color: HuntrColors.orange)
                        : Icon(Icons.circle_outlined,
                            key: const ValueKey('off'),
                            color: HuntrColors.muted.withValues(alpha: 0.6)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Explore's "Age" quick filter: a chip ("Age", or "Age 20-30") that opens
/// a sheet with the age range's slider (applied when let go) and Any age.
class AgeFilterChip extends StatelessWidget {
  const AgeFilterChip(
      {super.key, required this.range, required this.onChanged});

  final RangeValues range;
  final ValueChanged<RangeValues> onChanged;

  static const _any = RangeValues(ExploreFilters.minAge, ExploreFilters.maxAge);

  /// "20-30", "25+" (the top end means "and older").
  static String describe(RangeValues r) {
    final from = r.start.round(), to = r.end.round();
    if (to >= ExploreFilters.maxAge) return '$from+';
    return from == to ? '$from' : '$from-$to';
  }

  static bool isAny(RangeValues r) =>
      r.start <= ExploreFilters.minAge && r.end >= ExploreFilters.maxAge;

  @override
  Widget build(BuildContext context) {
    final any = isAny(range);
    return PillChip(
      key: const Key('ageChip'),
      icon: Icons.cake_outlined,
      label: any ? 'Age' : 'Age ${describe(range)}',
      dropdown: true,
      selected: !any,
      onSelected: (_) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AgeSheet(range: range, onChanged: onChanged),
      ),
    );
  }
}

class _AgeSheet extends StatefulWidget {
  const _AgeSheet({required this.range, required this.onChanged});

  final RangeValues range;
  final ValueChanged<RangeValues> onChanged;

  @override
  State<_AgeSheet> createState() => _AgeSheetState();
}

class _AgeSheetState extends State<_AgeSheet> {
  /// The slider's while dragging (Explore loads again only when let go).
  late RangeValues _range = widget.range;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Age',
      note: "People who hide their age always show.",
      onClear: AgeFilterChip.isAny(_range)
          ? null
          : () {
              setState(() => _range = AgeFilterChip._any);
              widget.onChanged(AgeFilterChip._any);
            },
      clearLabel: 'Any age',
      children: [
        Center(
          child: Text(
            AgeFilterChip.isAny(_range)
                ? 'Any age'
                : AgeFilterChip.describe(_range),
            key: const Key('ageRangeLabel'),
            style: TextStyle(
                color: HuntrColors.orange,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        const SizedBox(height: 8),
        RangeSlider(
          key: const Key('ageSlider'),
          values: _range,
          min: ExploreFilters.minAge,
          max: ExploreFilters.maxAge,
          divisions: (ExploreFilters.maxAge - ExploreFilters.minAge).round(),
          labels: RangeLabels('${_range.start.round()}',
              AgeFilterChip.describe(RangeValues(_range.end, _range.end))),
          onChanged: (v) => setState(() => _range = v),
          onChangeEnd: widget.onChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Text('${ExploreFilters.minAge.round()}',
                style: TextStyle(color: HuntrColors.muted)),
            const Spacer(),
            Text('${ExploreFilters.maxAge.round()}+',
                style: TextStyle(color: HuntrColors.muted)),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A quick filter's sheet: its title (Clear beside it), a line under it,
/// the choices, and Done.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    required this.onClear,
    this.note,
    this.clearLabel = 'Clear',
  });

  final String title;
  final String? note;
  final List<Widget> children;

  /// Null: nothing to clear (Clear greyed out).
  final VoidCallback? onClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style:
                        text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              TextButton(
                key: const Key('sheetClear'),
                onPressed: onClear,
                child: Text(clearLabel),
              ),
            ]),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(note!,
                    style: text.bodyMedium?.copyWith(color: HuntrColors.muted)),
              ),
            const SizedBox(height: 12),
            ...children,
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('sheetDone'),
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
