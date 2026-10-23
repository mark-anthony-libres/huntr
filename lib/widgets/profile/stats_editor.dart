import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';

/// The STATS part of Edit profile: Show Age, height, weight, body type,
/// ethnicity, relationship status and tribes, each with
/// "Do not show"; and the units heights and weights are shown in.
class StatsEditor extends StatelessWidget {
  const StatsEditor({super.key, required this.stats, required this.onChanged});

  final ProfileStats stats;
  final ValueChanged<ProfileStats> onChanged;

  static const _notShown = 'Do not show';

  @override
  Widget build(BuildContext context) {
    final units = stats.units;
    Future<void> pick<T>(String title, List<(T, String)> options, T? current,
        ProfileStats Function(T?) apply) async {
      final picked = await _pickOne<T>(context, title, options, current);
      if (picked != null) onChanged(apply(picked.value));
    }

    return Container(
      key: const Key('statsEditor'),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: HuntrColors.night,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF353944), width: 1.2),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(children: [
            const Icon(Icons.straighten_rounded,
                size: 18, color: HuntrColors.muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('STATS',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: HuntrColors.muted)),
            ),
            // the units I see heights and weights in
            SegmentedButton<MeasurementUnits>(
              key: const Key('statsUnits'),
              style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                      fontFamily: huntrFontFamily, fontSize: 12)),
              showSelectedIcon: false,
              segments: [
                for (final u in MeasurementUnits.values)
                  ButtonSegment(value: u, label: Text(u.label)),
              ],
              selected: {units},
              onSelectionChanged: (s) =>
                  onChanged(stats.copyWith(units: s.first)),
            ),
          ]),
        ),
        _Row(
          key: const Key('statShowAge'),
          label: 'Show Age',
          trailing: Switch(
            key: const Key('statShowAgeSwitch'),
            value: stats.showAge,
            onChanged: (v) => onChanged(stats.copyWith(showAge: v)),
          ),
        ),
        _Row(
          key: const Key('statHeight'),
          label: 'Height',
          value: stats.heightCm == null ? null : units.height(stats.heightCm!),
          onTap: () => pick<int>(
              'Height', _heights(units), stats.heightCm, stats.withHeight),
        ),
        _Row(
          key: const Key('statWeight'),
          label: 'Weight',
          value: stats.weightKg == null ? null : units.weight(stats.weightKg!),
          onTap: () => pick<int>(
              'Weight', _weights(units), stats.weightKg, stats.withWeight),
        ),
        _Row(
          key: const Key('statBodyType'),
          label: 'Body Type',
          value: stats.bodyType?.label,
          onTap: () => pick<BodyType>(
              'Body Type',
              [for (final v in BodyType.values) (v, v.label)],
              stats.bodyType,
              stats.withBodyType),
        ),
        _Row(
          key: const Key('statEthnicity'),
          label: 'Ethnicity',
          value: stats.ethnicity?.label,
          onTap: () => pick<Ethnicity>(
              'Ethnicity',
              [for (final v in Ethnicity.values) (v, v.label)],
              stats.ethnicity,
              stats.withEthnicity),
        ),
        _Row(
          key: const Key('statRelationship'),
          label: 'Relationship Status',
          value: stats.relationshipStatus?.label,
          onTap: () => pick<RelationshipStatus>(
              'Relationship Status',
              [for (final v in RelationshipStatus.values) (v, v.label)],
              stats.relationshipStatus,
              stats.withRelationship),
        ),
        _Row(
          key: const Key('statTribes'),
          label: 'My Tribes',
          value: stats.tribes.isEmpty
              ? null
              : [
                  for (final t in Tribe.values)
                    if (stats.tribes.contains(t)) t.label
                ].join(', '),
          last: true,
          onTap: () async {
            final picked = await _pickTribes(context, stats.tribes);
            if (picked != null) onChanged(stats.copyWith(tribes: picked));
          },
        ),
      ]),
    );
  }

  /// Heights to choose from, in [units] (stored as cm).
  static List<(int, String)> _heights(MeasurementUnits units) =>
      units == MeasurementUnits.metric
          ? [for (var cm = 140; cm <= 220; cm++) (cm, units.height(cm))]
          : [
              // 4'7" to 7'3", whole inches
              for (var inches = 55; inches <= 87; inches++)
                (
                  (inches * 2.54).round(),
                  units.height((inches * 2.54).round())
                ),
            ];

  /// Weights to choose from, in [units] (stored as kg).
  static List<(int, String)> _weights(MeasurementUnits units) {
    if (units == MeasurementUnits.metric) {
      return [for (var kg = 40; kg <= 200; kg++) (kg, units.weight(kg))];
    }
    // every 1 lb that lands on a different kg
    final seen = <int>{};
    return [
      for (var lb = 90; lb <= 440; lb++)
        if (seen.add((lb / 2.20462).round()))
          ((lb / 2.20462).round(), units.weight((lb / 2.20462).round())),
    ];
  }
}

/// A choice from a picker (a null value: "Do not show").
class _Picked<T> {
  const _Picked(this.value);
  final T? value;
}

Future<_Picked<T>?> _pickOne<T>(BuildContext context, String title,
        List<(T, String)> options, T? current) =>
    showModalBottomSheet<_Picked<T>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final all = <(T?, String)>[
          (null, StatsEditor._notShown),
          ...options,
        ];
        final selected = all.indexWhere((o) => o.$1 == current);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  key: const Key('statPicker'),
                  shrinkWrap: true,
                  // long lists (heights, weights) open at the current one
                  controller: ScrollController(
                      initialScrollOffset:
                          selected > 4 ? (selected - 3) * 56.0 : 0),
                  itemCount: all.length,
                  itemExtent: 56,
                  itemBuilder: (_, i) {
                    final (value, label) = all[i];
                    final isCurrent = i == selected;
                    return ListTile(
                      key: Key('statOption-$label'),
                      title: Text(label,
                          style: TextStyle(
                              color: value == null ? HuntrColors.muted : null)),
                      trailing: Icon(
                          isCurrent
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isCurrent
                              ? HuntrColors.orange
                              : HuntrColors.muted),
                      onTap: () => Navigator.of(context).pop(_Picked(value)),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );

/// Tribes: none, one or several. Null when dismissed.
Future<Set<Tribe>?> _pickTribes(BuildContext context, Set<Tribe> current) =>
    showModalBottomSheet<Set<Tribe>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        var chosen = {...current};
        return StatefulBuilder(
          builder: (context, setSheet) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('My Tribes',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Pick any that describe you, or none.',
                        style: TextStyle(color: HuntrColors.muted)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in Tribe.values)
                        FilterChip(
                          key: Key('tribe-${t.apiName}'),
                          label: Text(t.label),
                          selected: chosen.contains(t),
                          onSelected: (on) => setSheet(
                              () => on ? chosen.add(t) : chosen.remove(t)),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('tribesDone'),
                      onPressed: () => Navigator.of(context).pop(chosen),
                      child: const Text('Done'),
                    ),
                  ]),
            ),
          ),
        );
      },
    );

/// One stat: its name, its value (or "Do not show") and a chevron.
class _Row extends StatelessWidget {
  const _Row(
      {super.key,
      required this.label,
      this.value,
      this.onTap,
      this.trailing,
      this.last = false});

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: last
          ? const BorderRadius.vertical(bottom: Radius.circular(14))
          : BorderRadius.zero,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (trailing != null)
            trailing!
          else ...[
            Expanded(
              flex: 6,
              child: Text(value ?? StatsEditor._notShown,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: value == null ? HuntrColors.muted : Colors.white)),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: HuntrColors.muted),
          ],
        ]),
      ),
    );
  }
}
