import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class TournamentScheduleScreen extends ConsumerWidget {
  const TournamentScheduleScreen({
    super.key,
    this.asTab = false,
    this.canRecordResults = false,
  });

  final bool asTab;
  final bool canRecordResults;

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
        title: const Text('Tournament Schedule'),
      ),
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
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: const [
                    SizedBox(height: 72),
                    Icon(Icons.emoji_events_outlined, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No tournament schedule has been published.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _ScheduleCard(
                    schedule: rows[index],
                    canRecordResults: canRecordResults,
                    onOpenDocument: rows[index].documentUrl?.isNotEmpty == true
                        ? () => _openDocument(context, rows[index].documentUrl!)
                        : null,
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
  });

  final TournamentSchedule schedule;
  final bool canRecordResults;
  final VoidCallback? onOpenDocument;

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
                        '${schedule.fixtures.length} fixtures',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onOpenDocument != null)
                  TextButton.icon(
                    onPressed: onOpenDocument,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Document'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (schedule.fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No structured fixtures were added.'),
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
                    if (fixture.stage.isNotEmpty)
                      Text(
                        fixture.stage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(fixture.status.label),
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
