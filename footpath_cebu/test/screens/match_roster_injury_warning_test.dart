import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_performance_screen.dart';
import 'package:footpath_cebu/presentation/screens/match_roster_screen.dart';

class _InjuredRosterRepository extends MockMatchRepository {
  MatchPerformanceDraft? savedDraft;

  @override
  Future<List<MatchRosterPlayer>> fetchMatchRoster(
    String matchId, {
    bool includeOutOfSquad = false,
  }) async {
    final rows = await super.fetchMatchRoster(
      matchId,
      includeOutOfSquad: includeOutOfSquad,
    );
    return [
      for (final row in rows)
        MatchRosterPlayer(
          id: row.id,
          name: row.name,
          registeredPosition: row.registeredPosition,
          performance: row.performance,
          ratingStatus: row.ratingStatus,
          activeInjuryStatus: row.id == 'p1' ? InjuryStatus.active : null,
        ),
    ];
  }

  @override
  Future<MatchPerformance> savePerformance(
    String matchId,
    String playerId,
    MatchPerformanceDraft draft,
  ) {
    savedDraft = draft;
    return super.savePerformance(matchId, playerId, draft);
  }
}

void main() {
  testWidgets('Coordinator acknowledges an injury before opening statistics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final match = FootballMatch(
      id: 'm1',
      opponent: 'Cebu United',
      competition: 'Youth League',
      playedOn: DateTime(2026, 8, 27),
      venue: MatchVenue.home,
      ourScore: 2,
      opponentScore: 1,
    );
    final repository = _InjuredRosterRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matchRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: MatchRosterScreen(
            match: match,
            mode: MatchRosterMode.coordinator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Confirmed Active injury - review before entry'),
      findsOneWidget,
    );
    await tester.tap(find.text('Rhobert Ronaldo'));
    await tester.pumpAndSettle();

    expect(find.text('Active injury warning'), findsOneWidget);
    expect(
      find.textContaining('saving statistics will record this override'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue to statistics'));
    await tester.pumpAndSettle();

    expect(find.byType(EditMatchPerformanceScreen), findsOneWidget);
    final saveButton = find.byKey(const Key('save-match-statistics')).first;
    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.savedDraft?.injuryOverrideAcknowledged, isTrue);
  });
}
