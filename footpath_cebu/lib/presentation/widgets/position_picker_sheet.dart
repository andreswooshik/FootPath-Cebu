import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// Coach-only position picker: a modal bottom sheet listing every position,
/// grouped by line.
///
/// A sheet rather than a dropdown because ten options don't read well in a
/// popup menu on a phone, and grouping (keeper / defence / midfield / attack)
/// matches how a coach thinks about a squad. It also leaves room to show both
/// the code and the full name, which a dropdown does not.
///
/// Returns the chosen [PlayerPosition], or null if the coach dismissed it.
/// Selecting only returns a value — the caller confirms and saves, so a
/// mis-tap in a ten-item list is never destructive on its own.
Future<PlayerPosition?> showPositionPickerSheet({
  required BuildContext context,
  required String playerName,
  required PlayerPosition? current,
}) {
  return showModalBottomSheet<PlayerPosition>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _PositionPickerSheet(playerName: playerName, current: current),
  );
}

class _PositionPickerSheet extends StatelessWidget {
  const _PositionPickerSheet({required this.playerName, required this.current});

  final String playerName;
  final PlayerPosition? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        // Ten rows plus four group headers need ~810px, so on a 400x800 phone
        // the attack line sits below the fold and the sheet scrolls — measured,
        // not assumed. The rows are dense to keep that scroll to a flick. Capped
        // below full height so it still reads as a sheet over the profile.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current == null ? 'Assign Position' : 'Change Position',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playerName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final group in PositionGroup.values) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                      child: Text(
                        group.label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final position in PlayerPositionInfo.inGroup(group))
                      _PositionTile(
                        position: position,
                        selected: position == current,
                        onTap: () => Navigator.of(context).pop(position),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One position row: its code badge, full name, and a tick when it's current.
class _PositionTile extends StatelessWidget {
  const _PositionTile({
    required this.position,
    required this.selected,
    required this.onTap,
  });

  final PlayerPosition position;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return MotionPress(
      child: ListTile(
        onTap: onTap,
        selected: selected,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            position.code,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
        title: Text(
          position.label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: cs.primary, size: 20)
            : null,
      ),
    );
  }
}
