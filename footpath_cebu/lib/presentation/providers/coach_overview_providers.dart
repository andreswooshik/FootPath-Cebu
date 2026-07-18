import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

/// A read-model for the Coach Dashboard's "Team Overview" widget, combining the
/// squad roster with the training schedule into the few numbers a coach scans
/// first: how ready the team is to play, and what needs attention.
class TeamOverview {
  const TeamOverview({
    required this.squadSize,
    required this.readyCount,
    required this.alerts,
    required this.nextSession,
  });

  final int squadSize;

  /// Players cleared to play (academically eligible).
  final int readyCount;

  /// Things needing the coach's attention, most urgent first.
  final List<TeamAlert> alerts;

  /// The soonest upcoming session, or null when none is scheduled.
  final TrainingSession? nextSession;

  /// Share of the squad ready to play, 0–100 (0 when the squad is empty).
  int get readyPercent =>
      squadSize == 0 ? 0 : ((readyCount / squadSize) * 100).round();
}

enum AlertSeverity { critical, warning, info }

class TeamAlert {
  const TeamAlert({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;
  final AlertSeverity severity;
}

/// Derives the [TeamOverview] from the squad and schedule providers. Stays an
/// [AsyncValue] so the widget can show loading/error states consistently.
final teamOverviewProvider =
    Provider.autoDispose<AsyncValue<TeamOverview>>((ref) {
  final squadAsync = ref.watch(squadProvider);
  final upcomingAsync = ref.watch(upcomingSessionsProvider);

  return squadAsync.whenData((squad) {
    final upcoming = upcomingAsync.value ?? const <TrainingSession>[];

    final ready = squad
        .where((p) => p.eligibility == EligibilityStatus.eligible)
        .length;

    final ineligible = squad
        .where((p) => p.eligibility == EligibilityStatus.notEligible)
        .toList();
    final warnings = squad
        .where((p) => p.eligibility == EligibilityStatus.academicWarning)
        .toList();
    final unassigned = squad.where((p) => p.position == null).toList();

    final alerts = <TeamAlert>[
      if (ineligible.isNotEmpty)
        TeamAlert(
          title: '${ineligible.length} player'
              '${ineligible.length == 1 ? '' : 's'} benched by grades',
          detail: 'Not cleared to play — review before selection.',
          severity: AlertSeverity.critical,
        ),
      if (warnings.isNotEmpty)
        TeamAlert(
          title: '${warnings.length} academic warning'
              '${warnings.length == 1 ? '' : 's'}',
          detail: 'Grades slipping — keep an eye on their progress.',
          severity: AlertSeverity.warning,
        ),
      if (unassigned.isNotEmpty)
        TeamAlert(
          title: '${unassigned.length} player'
              '${unassigned.length == 1 ? '' : 's'} need a position',
          detail: 'Assign a position after evaluating them.',
          severity: AlertSeverity.info,
        ),
      if (upcoming.isEmpty)
        const TeamAlert(
          title: 'No upcoming sessions',
          detail: 'Schedule a training session to keep the squad moving.',
          severity: AlertSeverity.info,
        ),
    ];

    return TeamOverview(
      squadSize: squad.length,
      readyCount: ready,
      alerts: alerts,
      nextSession: upcoming.isEmpty ? null : upcoming.first,
    );
  });
});
