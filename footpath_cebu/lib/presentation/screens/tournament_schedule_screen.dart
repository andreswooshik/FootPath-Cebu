import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_tournament_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/screens/tournament_squad_screen.dart';
import 'package:footpath_cebu/presentation/widgets/app_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class TournamentScheduleScreen extends ConsumerWidget {
  const TournamentScheduleScreen({
    super.key,
    this.asTab = false,
    this.canRecordResults = false,
    this.canManage = false,
    this.canManageRosters = false,
  });

  final bool asTab;
  final bool canRecordResults;
  final bool canManage;
  final bool canManageRosters;

  Future<void> _openDocument(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the schedule document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(tournamentSchedulesProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !asTab,
        title: const Text('Schedule'),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EditTournamentScreen(),
                  ),
                );
                ref.invalidate(tournamentSchedulesProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Create tournament'),
            )
          : null,
      body: schedules.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            error,
            'Could not load the tournament schedule.',
          ),
          onRetry: () => ref.invalidate(tournamentSchedulesProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () => ref.refresh(tournamentSchedulesProvider.future),
          child: ResponsiveContent(
            child: rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      DashboardEmptyState(
                        icon: Icons.emoji_events_outlined,
                        title: canManage
                            ? 'No tournament plans yet'
                            : 'No published tournaments',
                        message: canManage
                            ? 'Create a tournament draft, add its age brackets, and publish it when ready.'
                            : 'Published tournament schedules will appear here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _ScheduleCard(
                      schedule: rows[index],
                      canRecordResults: canRecordResults,
                      canManageRosters: canManageRosters,
                      onManage: canManage
                          ? () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EditTournamentScreen(
                                    existing: rows[index],
                                  ),
                                ),
                              );
                              ref.invalidate(tournamentSchedulesProvider);
                            }
                          : null,
                      onOpenDocument:
                          rows[index].documentUrl?.isNotEmpty == true
                          ? () =>
                                _openDocument(context, rows[index].documentUrl!)
                          : null,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.canRecordResults,
    required this.onOpenDocument,
    required this.onManage,
    required this.canManageRosters,
  });

  final TournamentSchedule schedule;
  final bool canRecordResults;
  final VoidCallback? onOpenDocument;
  final VoidCallback? onManage;
  final bool canManageRosters;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        formatFullDate(schedule.startsOn),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onManage != null)
                  IconButton(
                    tooltip: 'Manage tournament',
                    onPressed: onManage,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppStatusChip(
                  label: schedule.isPublished ? 'Published' : 'Draft',
                  tone: schedule.isPublished
                      ? AppStatusTone.success
                      : AppStatusTone.neutral,
                  icon: schedule.isPublished
                      ? Icons.public_outlined
                      : Icons.edit_note_outlined,
                ),
                for (final bracket in schedule.ageBrackets)
                  Chip(label: Text(bracket.label)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (onOpenDocument != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenDocument,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open schedule document'),
              ),
            ),
            const Divider(height: 1),
          ],
          if (schedule.ageBrackets.isNotEmpty) ...[
            for (final bracket in schedule.ageBrackets)
              ListTile(
                dense: true,
                leading: const Icon(Icons.groups_outlined),
                title: Text('${bracket.label} division'),
                subtitle: Text(
                  '${bracket.scheduledAt == null ? 'Schedule date and time: TBD' : _bracketScheduleLabel(context, bracket.scheduledAt!)}\n'
                  '${bracket.squad == null ? 'Roster not started' : '${bracket.squad!.status.label} roster - ${bracket.squad!.entries.length} players'}',
                ),
                isThreeLine: true,
                onTap: canManageRosters || bracket.squad != null
                    ? () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TournamentSquadScreen(
                              tournamentTitle: schedule.title,
                              tournamentPublished: schedule.isPublished,
                              bracket: bracket,
                              canEdit: canManageRosters,
                            ),
                          ),
                        );
                      }
                    : null,
                trailing: canManageRosters || bracket.squad != null
                    ? const Icon(Icons.chevron_right)
                    : null,
              ),
            const Divider(height: 1),
          ],
          if (schedule.fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No game fixtures yet. Rosters can still be prepared.',
              ),
            )
          else
            for (final fixture in schedule.fixtures)
              _FixtureTile(
                fixture: fixture,
                canRecordResults: canRecordResults,
              ),
        ],
      ),
    );
  }
}

String _bracketScheduleLabel(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '${formatFullDate(local)} at $time';
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.fixture, required this.canRecordResults});

  final TournamentFixture fixture;
  final bool canRecordResults;

  @override
  Widget build(BuildContext context) {
    final kickoff = fixture.kickoffAt.toLocal();
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(kickoff));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vs ${fixture.opponent}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (fixture.ageBracketLabel != null ||
                        fixture.stage.isNotEmpty)
                      Text(
                        [
                          if (fixture.ageBracketLabel != null)
                            fixture.ageBracketLabel!,
                          if (fixture.stage.isNotEmpty) fixture.stage,
                        ].join(' - '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              AppStatusChip(
                label: fixture.status.label,
                tone: switch (fixture.status) {
                  TournamentFixtureStatus.scheduled => AppStatusTone.info,
                  TournamentFixtureStatus.postponed => AppStatusTone.warning,
                  TournamentFixtureStatus.cancelled => AppStatusTone.danger,
                  TournamentFixtureStatus.completed => AppStatusTone.success,
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${formatShortDate(kickoff)} at $time'),
          Text(
            [
              fixture.venue.label,
              if (fixture.location.isNotEmpty) fixture.location,
            ].join(' - '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (canRecordResults && fixture.canRecordResult) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditFootballMatchScreen(fixture: fixture),
                    ),
                  );
                },
                icon: const Icon(Icons.sports_score_outlined),
                label: const Text('Record result'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
