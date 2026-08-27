import 'package:flutter/material.dart';

import 'package:footpath_cebu/presentation/theme/app_theme.dart';

/// A gamified attendance widget: a circular progress ring around a flame and
/// the current streak, with motivating youth-friendly copy. Replaces the raw
/// "0%" attendance text on the dashboard.
///
/// The ring fills toward [goal] consecutive sessions; hitting the goal turns
/// the ring gold. A zero streak is framed as an invitation, not a failure.
class StreakCounter extends StatelessWidget {
  const StreakCounter({
    super.key,
    required this.streak,
    required this.presentPercent,
    this.goal = 5,
  });

  /// Consecutive most-recent sessions attended.
  final int streak;

  /// Overall present rate (0–100), shown as a supporting stat.
  final int presentPercent;

  /// Sessions-in-a-row that "completes" the ring.
  final int goal;

  bool get _onFire => streak >= goal;

  String get _headline {
    if (streak == 0) return 'Start your streak!';
    if (streak == 1) return "You're on the board!";
    if (_onFire) return "You're on fire!";
    return 'Keep it going!';
  }

  String get _subline {
    if (streak == 0) return 'Show up to your next session to light the flame.';
    return '$streak session${streak == 1 ? '' : 's'} in a row 🔥';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ring = _onFire ? AppColors.gold : AppColors.coral;
    final progress = goal == 0 ? 0.0 : (streak / goal).clamp(0.0, 1.0);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0, end: progress),
                    builder: (context, value, _) => SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(ring),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _onFire ? '🔥' : '⚡',
                        style: const TextStyle(fontSize: 18),
                      ),
                      Text(
                        '$streak',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _headline,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AttendanceChip(percent: presentPercent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceChip extends StatelessWidget {
  const _AttendanceChip({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    // Teal text at this size doesn't clear WCAG AA against a near-white chip
    // (measured ~3.4:1 vs the 4.5:1 minimum), so the tint carries the brand
    // colour and the label reads in the theme's dark on-surface text instead.
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tealLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$percent% show-up rate',
        style: TextStyle(
          color: onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
