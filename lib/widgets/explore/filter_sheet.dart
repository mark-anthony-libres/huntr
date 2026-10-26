import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

class _FilterSheetState extends State<FilterSheet> {
  late ExploreFilters f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    f = AppScope.read(context).filters;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dist = f.maxDistanceKm ?? 25;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('Sort by', style: text.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ExploreSort>(
                key: const Key('exploreSort'),
                showSelectedIcon: false,
                segments: [
                  for (final sort in ExploreSort.values)
                    ButtonSegment(
                        value: sort,
                        icon: Icon(sort.icon, size: 18),
                        label: Text(sort.label)),
                ],
                selected: {f.sort},
                onSelectionChanged: (choice) =>
                    setState(() => f = f.copyWith(sort: choice.first)),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Online now only'),
              value: f.onlineOnly,
              onChanged: (v) => setState(() => f = f.copyWith(onlineOnly: v)),
            ),
            const SizedBox(height: 8),
            Text(
                'Distance: ${f.maxDistanceKm == null ? 'Any' : 'up to ${dist.round()} km'}',
                style: text.titleSmall),
            Slider(
              value: dist,
              min: 1,
              max: 25,
              divisions: 24,
              label: dist >= 25 ? 'Any' : '${dist.round()} km',
              onChanged: (v) => setState(() => f = v >= 25
                  ? f.copyWith(clearDistance: true)
                  : f.copyWith(maxDistanceKm: v)),
            ),
            Text(
                'Age: ${f.ageRange.start.round()} - ${f.ageRange.end.round()}${f.ageRange.end >= 60 ? '+' : ''}',
                style: text.titleSmall),
            RangeSlider(
              values: f.ageRange,
              min: 18,
              max: 60,
              divisions: 42,
              onChanged: (v) => setState(() => f = f.copyWith(ageRange: v)),
            ),
            const SizedBox(height: 4),
            Text('Looking for', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in LookingFor.values)
                  FilterChip(
                    avatar: Icon(l.icon, size: 18),
                    label: Text(l.label),
                    showCheckmark: false,
                    selected: f.lookingFor.contains(l),
                    onSelected: (v) {
                      final next = {...f.lookingFor};
                      v ? next.add(l) : next.remove(l);
                      setState(() => f = f.copyWith(lookingFor: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => f = ExploreFilters(query: f.query)),
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    AppScope.read(context).filters = f;
                    Navigator.pop(context);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Show results'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}
