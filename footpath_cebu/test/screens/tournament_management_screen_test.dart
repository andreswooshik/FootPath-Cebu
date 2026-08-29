import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/screens/edit_tournament_screen.dart';
import 'package:footpath_cebu/presentation/screens/tournament_schedule_screen.dart';

TournamentSchedule _draft() => TournamentSchedule(
  id: 'draft-1',
  title: 'Sinulog Cup',
  startsOn: DateTime(2026, 9, 20),
  isPublished: false,
  publishedAt: null,
  updatedAt: DateTime(2026, 8, 29),
  ageBrackets: const [TournamentAgeBracket(id: 'u8', maxAge: 8, label: 'U8')],
  fixtures: const [],
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
    expect(find.text('Maximum age'), findsOneWidget);
    expect(find.text('Add optional schedule date and time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
