import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_performance_screen.dart';
import 'package:footpath_cebu/presentation/screens/match_roster_screen.dart';

class _TournamentMatchRepository extends MockMatchRepository {
  @override
  Future<List<MatchRosterPlayer>> fetchMatchRoster(
    String matchId, {
    bool includeOutOfSquad = false,
  }) async {
    final member = MatchRosterPlayer(
      id: 'member',
      name: 'Published Member',
      registeredPosition: 'CM',
      tournamentPosition: 'CAM',
      performance: null,
      ratingStatus: MatchRatingStatus.awaitingStatistics,
      inTournamentSquad: true,
    );
    if (!includeOutOfSquad) return [member];
    return [
      member,
      const MatchRosterPlayer(
        id: 'replacement',
        name: 'Eligible Replacement',
        registeredPosition: 'RW',
        performance: null,
        ratingStatus: MatchRatingStatus.awaitingStatistics,
        requiresSquadOverride: true,
      ),
      const MatchRosterPlayer(
        id: 'blocked',
        name: 'Blocked Player',
        registeredPosition: 'ST',
        performance: null,
        ratingStatus: MatchRatingStatus.awaitingStatistics,
        requiresSquadOverride: true,
        isSelectable: false,
        availability: 'BLOCKED',
        availabilityReason: 'Unavailable.',
      ),
    ];
  }
}

FootballMatch _match() => FootballMatch(
  id: 'm1',
  opponent: 'Cebu United',
  competition: 'Sinulog Cup',
  playedOn: DateTime(2026, 8, 27),
  venue: MatchVenue.neutral,
  ourScore: 2,
  opponentScore: 1,
  fixtureId: 'fixture-1',
  recordSource: MatchRecordSource.scheduled,
  ageBracketId: 'bracket-8',
  ageBracketLabel: 'U8',
);

Future<void> _pump(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(_TournamentMatchRepository()),
      ],
      child: MaterialApp(
        home: MatchRosterScreen(
          match: _match(),
          mode: MatchRosterMode.coordinator,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(390, 1100), Size(820, 1180)]) {
    testWidgets(
      'Coordinator records a required squad exception at ${size.width.toInt()}px',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(tester, size);

        expect(find.text('U8 published squad'), findsOneWidget);
        expect(find.text('Published Member'), findsOneWidget);
        expect(find.text('Eligible Replacement'), findsNothing);
        await tester.tap(find.byKey(const Key('add-out-of-squad-player')));
        await tester.pumpAndSettle();

        expect(find.text('Eligible Replacement'), findsOneWidget);
        expect(find.text('Blocked Player'), findsNothing);
        await tester.tap(find.text('Eligible Replacement'));
        await tester.tap(find.byKey(const Key('continue-squad-exception')));
        await tester.pump();
        expect(
          find.text('Enter the Coordinator exception reason.'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('squad-exception-reason')),
          'Organizer-approved late replacement.',
        );
        await tester.tap(find.byKey(const Key('continue-squad-exception')));
        await tester.pumpAndSettle();

        expect(find.byType(EditMatchPerformanceScreen), findsOneWidget);
        final editor = tester.widget<EditMatchPerformanceScreen>(
          find.byType(EditMatchPerformanceScreen),
        );
        expect(editor.player.id, 'replacement');
        expect(
          editor.squadOverrideReason,
          'Organizer-approved late replacement.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
