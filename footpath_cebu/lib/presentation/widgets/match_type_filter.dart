import 'package:flutter/material.dart';

enum MatchTypeFilter { all, regular, tournaments }

extension MatchTypeFilterInfo on MatchTypeFilter {
  String get label => switch (this) {
    MatchTypeFilter.all => 'All Matches',
    MatchTypeFilter.regular => 'Regular Matches',
    MatchTypeFilter.tournaments => 'Tournaments',
  };
}

/// Visible, wrapping match-type navigation that remains usable on phones and
/// spreads naturally across a tablet without hiding options in a menu.
class MatchTypeFilterBar extends StatelessWidget {
  const MatchTypeFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final MatchTypeFilter selected;
  final ValueChanged<MatchTypeFilter> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Match type filter',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in MatchTypeFilter.values)
          ChoiceChip(
            key: ValueKey('matchFilter-${filter.name}'),
            label: Text(filter.label),
            selected: selected == filter,
            showCheckmark: false,
            onSelected: (_) => onSelected(filter),
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
      ],
    ),
  );
}
