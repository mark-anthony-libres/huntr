import 'package:flutter/material.dart';
import '../../theme.dart';

/// Explore with nobody to show: either the filters (or search) leave no one,
/// or there is simply nobody nearby yet.
class EmptyExplore extends StatelessWidget {
  const EmptyExplore({
    super.key,
    required this.filtered,
    required this.onClear,
    this.onRefresh,
  });

  /// Filters or a search are on (so clearing them may help).
  final bool filtered;
  final VoidCallback onClear;

  /// Loads the list again (when nobody is nearby); none hides the button.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(filtered ? Icons.travel_explore : Icons.person_search_outlined,
              size: 56, color: HuntrColors.muted),
          const SizedBox(height: 12),
          Text(filtered ? 'Nobody matches these filters' : 'No one nearby yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              filtered
                  ? 'Try widening the distance or age range.'
                  : 'People near you will show up here as they join.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: HuntrColors.muted)),
          if (filtered || onRefresh != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: Key(filtered ? 'exploreClearFilters' : 'exploreRefresh'),
              onPressed: filtered ? onClear : onRefresh,
              icon: Icon(
                  filtered
                      ? Icons.filter_alt_off_outlined
                      : Icons.refresh_rounded,
                  size: 18),
              label: Text(filtered ? 'Clear filters' : 'Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}
