import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/screens/tournament_squad_screen.dart';

const _draftBracket = TournamentAgeBracket(
  id: 'bracket-1',
  maxAge: 12,
  label: 'U12',
);

void main() {
  testWidgets('Coach sees eligibility states on a compact phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TournamentSquadScreen(
            tournamentTitle: 'Sinulog Cup',
            tournamentPublished: false,
            bracket: _draftBracket,
            canEdit: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Draft preparation is open'), findsOneWidget);
    expect(find.text('Alex Santos'), findsOneWidget);
    expect(find.text('Jamie Cruz'), findsOneWidget);
    expect(find.text('Sam Reyes'), findsOneWidget);
    expect(find.textContaining('Overage for this bracket'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Coach selects a player and assigns an optional position', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TournamentSquadScreen(
            tournamentTitle: 'Sinulog Cup',
            tournamentPublished: true,
            bracket: _draftBracket,
            canEdit: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alex Santos'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Tournament position (optional)'), findsOneWidget);
    expect(find.text('Publish roster'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only club view shows no medical details', (tester) async {
    const bracket = TournamentAgeBracket(
      id: 'bracket-1',
      maxAge: 12,
      label: 'U12',
      squad: TournamentSquad(
        id: 'squad-1',
        bracketId: 'bracket-1',
        status: TournamentSquadStatus.published,
        entries: [
          TournamentSquadEntry(
            id: 'entry-1',
            playerId: '8',
            playerName: 'Alex Santos',
            tournamentPosition: 'CM',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TournamentSquadScreen(
            tournamentTitle: 'Sinulog Cup',
            tournamentPublished: true,
            bracket: bracket,
            canEdit: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alex Santos'), findsOneWidget);
    expect(find.text('CM'), findsOneWidget);
    expect(find.textContaining('injury'), findsNothing);
  });
}
