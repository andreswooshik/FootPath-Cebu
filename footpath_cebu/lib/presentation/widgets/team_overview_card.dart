import 'package:flutter/material.dart';

import 'package:footpath_cebu/presentation/providers/coach_overview_providers.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';

/// The Coach Dashboard's "Team Overview" combines the next session with the
/// alerts needing attention. School clubs also receive academic clearance;
/// independent clubs do not see school-only eligibility concepts.
class TeamOverviewCard extends StatelessWidget {
  const TeamOverviewCard({super.key, required this.overview});

  final TeamOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Team Overview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (overview.academicEligibilityApplicable)
              Row(
                children: [
                  _ReadyGauge(percent: overview.readyPercent),
                  const SizedBox(width: 18),
                  Expanded(child: _NextSession(overview: overview)),
                ],
              )
            else
              _NextSession(overview: overview),
            if (overview.alerts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'Needs attention',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final alert in overview.alerts) _AlertRow(alert: alert),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadyGauge extends StatelessWidget {
  const _ReadyGauge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: percent / 100),
              builder: (context, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(AppColors.teal),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Text(
                'ready',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextSession extends StatelessWidget {
  const _NextSession({required this.overview});

  final TeamOverview overview;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = overview.nextSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          overview.academicEligibilityApplicable
              ? '${overview.readyCount} of ${overview.squadSize} cleared to play'
              : '${overview.squadSize} player'
                    '${overview.squadSize == 1 ? '' : 's'} in this squad',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.event, size: 16, color: AppColors.teal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                session == null
                    ? 'No sessions scheduled'
                    : 'Next: ${session.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (session != null) ...[
          const SizedBox(height: 2),
          Text(
            '${_months[session.date.month - 1]} ${session.date.day}'
            ' · ${session.startTime}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final TeamAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = switch (alert.severity) {
      AlertSeverity.critical => (const Color(0xFFE53935), Icons.error_outline),
      AlertSeverity.warning => (AppColors.coral, Icons.warning_amber_rounded),
      AlertSeverity.info => (AppColors.teal, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  alert.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
