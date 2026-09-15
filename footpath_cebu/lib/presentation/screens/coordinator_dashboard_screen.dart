import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

/// A compact competitive overview. Member-management totals live in People,
/// so the coordinator's home screen stays focused on matches and decisions.
class CoordinatorDashboardScreen extends ConsumerWidget {
  const CoordinatorDashboardScreen({
    super.key,
    required this.onOpenPeople,
    required this.onOpenSchedule,
    required this.onOpenOperations,
  });

  final VoidCallback onOpenPeople;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenOperations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules =
        ref.watch(tournamentSchedulesProvider).value ??
        const <TournamentSchedule>[];
    final matches =
        ref.watch(footballMatchesProvider).value ?? const <FootballMatch>[];
    final injuries =
        ref.watch(clubInjuriesProvider).value ?? const <InjuryRecord>[];
    final players = ref.watch(squadProvider).value ?? const <Player>[];
    final summary = _SeasonSummary.from(matches);
    final fixture = _nextFixture(schedules);
    final reviews = injuries.where((record) => record.canReview).length;
    final missingResults = schedules
        .expand((schedule) => schedule.fixtures)
        .where(
          (item) => !item.hasResult && !item.kickoffAt.isAfter(DateTime.now()),
        )
        .length;
    final unassigned = players
        .where((player) => player.position == null)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FootPath Cebu'),
        actions: const [NotificationBell(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(tournamentSchedulesProvider.future),
            ref.refresh(footballMatchesProvider.future),
            ref.refresh(clubInjuriesProvider.future),
            ref.refresh(squadProvider.future),
          ]);
        },
        child: ResponsiveContent(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              _SectionTitle(
                overline: '${DateTime.now().year} Season',
                title: 'Tournament record',
                action: 'View all',
                onAction: onOpenSchedule,
              ),
              const SizedBox(height: 10),
              _RecordSurface(summary: summary),
              const SizedBox(height: 28),
              const _SectionTitle(title: 'Next fixture'),
              const SizedBox(height: 10),
              if (fixture == null)
                _EmptySurface(
                  icon: Icons.event_available_outlined,
                  title: 'No upcoming fixture',
                  message: 'Published tournament fixtures will appear here.',
                  action: 'Manage schedule',
                  onAction: onOpenSchedule,
                )
              else
                _FixtureSurface(fixture: fixture, onOpen: onOpenSchedule),
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'Recent tournaments',
                action: 'See all',
                onAction: onOpenSchedule,
              ),
              const SizedBox(height: 10),
              _TournamentRows(schedules: schedules, onOpen: onOpenSchedule),
              const SizedBox(height: 28),
              const _SectionTitle(title: 'Needs attention'),
              const SizedBox(height: 10),
              _AttentionRows(
                injuryReviews: reviews,
                missingResults: missingResults,
                unassignedPlayers: unassigned,
                onOpenOperations: onOpenOperations,
                onOpenPeople: onOpenPeople,
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ScheduledFixture? _nextFixture(List<TournamentSchedule> schedules) {
    final now = DateTime.now();
    final entries = <_ScheduledFixture>[];
    for (final schedule in schedules) {
      for (final fixture in schedule.fixtures) {
        if (!fixture.hasResult && !fixture.kickoffAt.isBefore(now)) {
          entries.add(_ScheduledFixture(schedule: schedule, fixture: fixture));
        }
      }
    }
    entries.sort((a, b) => a.fixture.kickoffAt.compareTo(b.fixture.kickoffAt));
    return entries.isEmpty ? null : entries.first;
  }
}

class _SeasonSummary {
  const _SeasonSummary({
    required this.wins,
    required this.draws,
    required this.losses,
  });

  final int wins;
  final int draws;
  final int losses;

  int get total => wins + draws + losses;
  int get winRate => total == 0 ? 0 : ((wins / total) * 100).round();
  String get record => '${wins}W  ${draws}D  ${losses}L';

  factory _SeasonSummary.from(List<FootballMatch> matches) {
    var wins = 0;
    var draws = 0;
    var losses = 0;
    for (final match in matches) {
      if (match.ourScore > match.opponentScore) wins++;
      if (match.ourScore == match.opponentScore) draws++;
      if (match.ourScore < match.opponentScore) losses++;
    }
    return _SeasonSummary(wins: wins, draws: draws, losses: losses);
  }
}

class _ScheduledFixture {
  const _ScheduledFixture({required this.schedule, required this.fixture});

  final TournamentSchedule schedule;
  final TournamentFixture fixture;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.overline,
    this.action,
    this.onAction,
  });

  final String title;
  final String? overline;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overline != null) ...[
              Text(overline!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
            ],
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class _RecordSurface extends StatelessWidget {
  const _RecordSurface({required this.summary});
  final _SeasonSummary summary;

  @override
  Widget build(BuildContext context) => _Surface(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: AppColors.tealLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.emoji_events_outlined,
                  color: AppColors.tealDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${summary.wins}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'Matches won',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      'Recorded results this season',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: _MiniStat(value: summary.record, label: 'Match record'),
              ),
              const SizedBox(height: 38, child: VerticalDivider(width: 1)),
              Expanded(
                child: _MiniStat(
                  value: '${summary.winRate}%',
                  label: 'Win rate',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _FixtureSurface extends StatelessWidget {
  const _FixtureSurface({required this.fixture, required this.onOpen});
  final _ScheduledFixture fixture;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Surface(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fixture.schedule.title,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              _Tag(label: fixture.schedule.lifecycleStatus.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'FootPath FC vs ${fixture.fixture.opponent}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _DetailLine(
            icon: Icons.calendar_today_outlined,
            text:
                '${formatShortDate(fixture.fixture.kickoffAt)}  |  ${_formatTime(fixture.fixture.kickoffAt)}',
          ),
          const SizedBox(height: 6),
          _DetailLine(
            icon: Icons.location_on_outlined,
            text: fixture.fixture.location,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpen,
              child: const Text('Open fixture'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TournamentRows extends StatelessWidget {
  const _TournamentRows({required this.schedules, required this.onOpen});
  final List<TournamentSchedule> schedules;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (schedules.isEmpty) {
      return _EmptySurface(
        icon: Icons.emoji_events_outlined,
        title: 'No tournaments yet',
        message: 'Create a schedule to begin tracking your season.',
        action: 'Create tournament',
        onAction: onOpen,
      );
    }
    final entries = schedules.take(3).toList(growable: false);
    return _Surface(
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            ListTile(
              title: Row(
                children: [
                  Expanded(child: Text(entries[index].title)),
                  const SizedBox(width: 8),
                  _Tag(label: entries[index].lifecycleStatus.label),
                ],
              ),
              subtitle: Text(_subtitle(entries[index])),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpen,
            ),
            if (index < entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  String _subtitle(TournamentSchedule schedule) {
    final next =
        schedule.fixtures.where((fixture) => !fixture.hasResult).toList()
          ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    return next.isEmpty
        ? '${schedule.fixtures.length} fixtures'
        : 'Next fixture: ${formatShortDate(next.first.kickoffAt)}';
  }
}

class _AttentionRows extends StatelessWidget {
  const _AttentionRows({
    required this.injuryReviews,
    required this.missingResults,
    required this.unassignedPlayers,
    required this.onOpenOperations,
    required this.onOpenPeople,
  });
  final int injuryReviews;
  final int missingResults;
  final int unassignedPlayers;
  final VoidCallback onOpenOperations;
  final VoidCallback onOpenPeople;

  @override
  Widget build(BuildContext context) => _Surface(
    child: Column(
      children: [
        _AttentionRow(
          icon: Icons.health_and_safety_outlined,
          title: injuryReviews == 0
              ? 'No injury reviews waiting'
              : '$injuryReviews injury ${injuryReviews == 1 ? 'report' : 'reports'} awaiting review',
          subtitle: 'Medical',
          urgent: injuryReviews > 0,
          onTap: onOpenOperations,
        ),
        const Divider(height: 1),
        _AttentionRow(
          icon: Icons.description_outlined,
          title: missingResults == 0
              ? 'All past fixtures have results'
              : '$missingResults fixtures without recorded results',
          subtitle: 'Match operations',
          onTap: onOpenOperations,
        ),
        const Divider(height: 1),
        _AttentionRow(
          icon: Icons.people_outline,
          title: unassignedPlayers == 0
              ? 'All players have a position'
              : '$unassignedPlayers players without a position',
          subtitle: 'Roster readiness',
          onTap: onOpenPeople,
        ),
      ],
    ),
  );
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.urgent = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool urgent;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: urgent ? AppColors.coral : null),
    title: Text(
      title,
      style: urgent
          ? const TextStyle(color: AppColors.coral, fontWeight: FontWeight.w600)
          : null,
    ),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}

class _EmptySurface extends StatelessWidget {
  const _EmptySurface({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => _Surface(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}

String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}
