import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';
import 'package:footpath_cebu/presentation/screens/eligibility_history_screen.dart';

/// A repository with no history — the mock seeds every player, so the empty
/// state needs an override.
class _EmptyRepository implements EligibilityHistoryRepository {
  @override
  Future<List<EligibilityChange>> fetchHistoryForPlayer(String playerId) async {
    return const [];
  }
}

void main() {
  /// Repository providers default to the in-memory mocks in a test
  /// environment; the mock seeds a four-entry timeline ending back at
  /// Eligible.
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: EligibilityHistoryScreen(
            playerId: 'p1',
            playerName: 'Rhobert Ronaldo',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the timeline newest first with old → new badges',
      (tester) async {
    await pump(tester);

    expect(find.text('Eligibility · Rhobert Ronaldo'), findsOneWidget);
    // Four transitions; "Eligible" appears as old or new status across them.
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.text('Academic Warning'), findsNWidgets(2));
    // Who made each change is the role, never a staff member's name.
    expect(find.textContaining('by School Staff'), findsNWidgets(3));
    expect(find.textContaining('by System'), findsOneWidget);
  });

  testWidgets('the first-ever status shows a single badge, no arrow',
      (tester) async {
    await pump(tester);

    // The seed's oldest entry (null oldStatus) renders only its new status;
    // the three transitions each render an arrow.
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(3));
  });

  testWidgets('a player with no changes sees the empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eligibilityHistoryRepositoryProvider
              .overrideWithValue(_EmptyRepository()),
        ],
        child: const MaterialApp(
          home: EligibilityHistoryScreen(
            playerId: 'p1',
            playerName: 'Rhobert Ronaldo',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No status changes yet'), findsOneWidget);
  });
}
