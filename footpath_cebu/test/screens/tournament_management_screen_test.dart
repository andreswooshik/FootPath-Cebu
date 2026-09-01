import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_tournament_screen.dart';
import 'package:footpath_cebu/presentation/screens/record_tournament_result_screen.dart';
import 'package:footpath_cebu/presentation/screens/tournament_schedule_screen.dart';

TournamentSchedule _draft() => TournamentSchedule(
  id: 'draft-1',
  title: 'Sinulog Cup',
  venue: 'Cebu City Sports Center',
  startsOn: DateTime(2026, 9, 20),
  isPublished: false,
  lifecycleStatus: TournamentLifecycleStatus.draft,
  hasDocument: false,
  publishedAt: null,
  updatedAt: DateTime(2026, 8, 29),
  ageBrackets: const [TournamentAgeBracket(id: 'u8', maxAge: 8, label: 'U8')],
  fixtures: const [],
);

TournamentSchedule _completed() => TournamentSchedule(
  id: 'cup-1',
  title: 'Cebu Youth Cup',
  venue: 'Dynamic Herb Sports Stadium',
  startsOn: DateTime(2026, 8, 27),
  isPublished: true,
  lifecycleStatus: TournamentLifecycleStatus.completed,
  hasDocument: false,
  publishedAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 27),
  ageBrackets: const [
    TournamentAgeBracket(id: 'u16', maxAge: 16, label: 'U16'),
  ],
  fixtures: [
    TournamentFixture(
      id: 'fixture-1',
      scheduleId: 'cup-1',
      tournament: 'Cebu Youth Cup',
      stage: 'Final',
      opponent: 'Mandaue FC',
      kickoffAt: DateTime(2026, 8, 27, 14),
      venue: MatchVenue.neutral,
      location: 'Cebu City Sports Center',
      status: TournamentFixtureStatus.completed,
      matchId: 'match-1',
      ageBracketId: 'u16',
      ageBracketLabel: 'U16',
      ourScore: 2,
      opponentScore: 1,
      outcome: 'WIN',
      linkedMatch: FootballMatch(
        id: 'match-1',
        opponent: 'Mandaue FC',
        competition: 'Cebu Youth Cup',
        playedOn: DateTime(2026, 8, 27),
        venue: MatchVenue.neutral,
        ourScore: 2,
        opponentScore: 1,
        category: MatchCategory.tournament,
      ),
    ),
  ],
);

TournamentSchedule _readyForResult() {
  final kickoff = DateTime.now().subtract(const Duration(days: 1));
  return TournamentSchedule(
    id: 'cup-ready',
    title: 'Cebu Invitational',
    venue: 'Abellana Field',
    startsOn: kickoff,
    isPublished: true,
    lifecycleStatus: TournamentLifecycleStatus.inProgress,
    hasDocument: true,
    documentUrl: 'https://example.test/schedule.pdf',
    publishedAt: kickoff.subtract(const Duration(days: 5)),
    updatedAt: kickoff,
    ageBrackets: const [
      TournamentAgeBracket(
        id: 'u16-ready',
        maxAge: 16,
        label: 'U16',
        squad: TournamentSquad(
          id: 'squad-1',
          bracketId: 'u16-ready',
          status: TournamentSquadStatus.published,
          entries: [
            TournamentSquadEntry(
              id: 'entry-1',
              playerId: 'player-1',
              playerName: 'Juan Dela Cruz',
              tournamentPosition: 'CM',
            ),
          ],
        ),
      ),
    ],
    fixtures: [
      TournamentFixture(
        id: 'fixture-ready',
        scheduleId: 'cup-ready',
        tournament: 'Cebu Invitational',
        stage: 'Group A',
        opponent: 'Lapu-Lapu FC',
        kickoffAt: kickoff,
        venue: MatchVenue.home,
        location: 'Abellana Field',
        status: TournamentFixtureStatus.scheduled,
        ageBracketId: 'u16-ready',
        ageBracketLabel: 'U16',
      ),
    ],
  );
}

void main() {
  testWidgets('Coordinator schedule tab exposes tournament management', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TournamentScheduleScreen(asTab: true, canManage: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FloatingActionButton, 'Create Tournament'),
      findsOneWidget,
    );
    expect(find.widgetWithText(Tab, 'Drafts'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Published'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Completed'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Published'));
    await tester.pumpAndSettle();
    expect(find.text('Cebu Youth Cup'), findsOneWidget);
    expect(find.text('U12'), findsWidgets);
    expect(find.byTooltip('Manage tournament'), findsOneWidget);
  });

  testWidgets('draft editor is usable on a compact phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditTournamentScreen(existing: _draft())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sinulog Cup'), findsWidgets);
    expect(find.text('Draft'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Cebu City Sports Center'),
      findsOneWidget,
    );
    expect(find.text('Publish tournament'), findsOneWidget);

    await tester.ensureVisible(find.text('Age Brackets'));
    await tester.tap(find.text('Age Brackets'));
    await tester.pumpAndSettle();
    expect(find.text('U8 division'), findsOneWidget);
    expect(find.text('Add bracket'), findsOneWidget);
    await tester.tap(find.text('Add bracket'));
    await tester.pumpAndSettle();
    expect(find.text('Add age bracket'), findsOneWidget);
    expect(find.text('Save bracket'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bracket editor opens cleanly on a tablet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditTournamentScreen(existing: _draft())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Age Brackets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bracket'));
    await tester.pumpAndSettle();

    expect(find.text('Add age bracket'), findsOneWidget);
    expect(find.text('Age bracket'), findsOneWidget);
    expect(find.text('Choose U3 through U21.'), findsOneWidget);
    expect(find.text('Add optional schedule date and time'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tournament-age-bracket-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('U3'), findsOneWidget);
    expect(find.text('U21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixture management is touch friendly at SM-X200 dimensions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditTournamentScreen(existing: _draft())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fixtures'));
    await tester.pumpAndSettle();
    expect(find.text('Manual Fixtures'), findsOneWidget);
    expect(find.text('Add Fixture'), findsOneWidget);
    expect(find.text('All brackets'), findsOneWidget);
    expect(find.text('All stages'), findsOneWidget);
    expect(find.text('All statuses'), findsOneWidget);

    await tester.ensureVisible(find.text('Document'));
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();
    expect(find.text('Official Schedule Document'), findsOneWidget);
    expect(find.text('Choose PDF, JPG, or PNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('result capture exposes published squad statistics on SM-X200', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tournament = _readyForResult();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RecordTournamentResultScreen(
            tournament: tournament,
            fixture: tournament.fixtures.single,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Record Tournament Result'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Record Result and Player Statistics'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Edit Statistics'), findsOneWidget);
    await tester.tap(find.text('Edit Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Match position'), findsOneWidget);
    expect(find.text('Passes attempted'), findsOneWidget);
    expect(find.text('Saves (GK)'), findsOneWidget);
    expect(find.text('Save Statistics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed fixture shows score, outcome, and linked details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tournamentSchedulesProvider.overrideWith((ref) => [_completed()]),
        ],
        child: const MaterialApp(home: TournamentScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('vs Mandaue FC'), findsOneWidget);
    expect(find.text('Dynamic Herb Sports Stadium'), findsOneWidget);
    expect(find.text('U16 - Final'), findsOneWidget);
    expect(find.text('2-1 · Win'), findsOneWidget);
    expect(find.text('Cebu Youth Cup · U16 · Final'), findsOneWidget);
    expect(find.text('Linked match Neutral · Tournament'), findsOneWidget);
  });
}
