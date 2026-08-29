import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_injury_repository.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_injuries_screen.dart';

void main() {
  testWidgets('Coordinator can confirm a Pending injury report', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockInjuryRepository();
    final pendingSave = repository.saveInjury(
      InjuryRecord(
        playerId: 'p1',
        description: 'Home ankle injury',
        status: InjuryStatus.active,
        occurredOn: DateTime(2026, 8, 27),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await pendingSave;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [injuryRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: CoordinatorInjuriesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home ankle injury'), findsOneWidget);
    expect(find.text('Pending confirmation'), findsOneWidget);
    await tester.tap(find.text('Home ankle injury'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Injury report confirmed.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
  });

  for (final size in const [Size(390, 1000), Size(820, 1180)]) {
    testWidgets(
      'injury reporting uses a searchable adaptive player picker at ${size.width.toInt()}px',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              injuryRepositoryProvider.overrideWithValue(
                MockInjuryRepository(),
              ),
            ],
            child: const MaterialApp(home: CoordinatorInjuriesScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Report injury'));
        await tester.pumpAndSettle();

        expect(find.text('Choose player'), findsOneWidget);
        expect(find.text('Search players'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Mika');
        await tester.pump();
        final picker = find.byKey(const Key('injury-player-picker'));
        expect(
          find.descendant(of: picker, matching: find.text('Mika Santos')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: picker, matching: find.text('Rhobert Ronaldo')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
