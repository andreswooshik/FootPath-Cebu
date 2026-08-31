import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_tournament_screen.dart';
import 'package:footpath_cebu/presentation/screens/tournament_schedule_screen.dart';

TournamentSchedule _draft() => TournamentSchedule(
  id: 'draft-1',
  title: 'Sinulog Cup',
  venue: 'Cebu City Sports Center',
  startsOn: DateTime(2026, 9, 20),
  isPublished: false,
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
      find.widgetWithText(FloatingActionButton, 'Create tournament'),
      findsOneWidget,
    );
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

    expect(find.text('Tournament draft'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Cebu City Sports Center'),
      findsOneWidget,
    );
    expect(find.text('U8 division'), findsOneWidget);
    expect(find.text('Add bracket'), findsOneWidget);
    expect(find.text('Publish tournament'), findsOneWidget);

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
