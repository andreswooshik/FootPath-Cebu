import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';
import 'package:footpath_cebu/presentation/screens/eligibility_history_screen.dart';

/// A repository with no history — the mock seeds every player, so the empty
/// state needs an override.
class _EmptyRepository implements EligibilityHistoryRepository {
  @override
  Future<EligibilityStatus> updateEligibility(
    String playerId,
    EligibilityStatus status,
  ) async => status;

  @override
  Future<List<EligibilityChange>> fetchHistoryForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    return const [];
  }
}

class _DelayedRepository extends _EmptyRepository {
  final result = Completer<EligibilityStatus>();
  String? savedPlayerId;
  EligibilityStatus? savedStatus;

  @override
  Future<EligibilityStatus> updateEligibility(
    String playerId,
    EligibilityStatus status,
  ) {
    savedPlayerId = playerId;
    savedStatus = status;
    return result.future;
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

  testWidgets('shows the timeline newest first with old → new badges', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Eligibility · Rhobert Ronaldo'), findsOneWidget);
    // Four transitions; "Eligible" appears as old or new status across them.
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.text('Academic Warning'), findsNWidgets(2));
    // Who made each change is the role, never a Coordinator's name.
    expect(find.textContaining('by Club Coordinator'), findsNWidgets(3));
    expect(find.textContaining('by System'), findsOneWidget);
    expect(find.byTooltip('Update eligibility'), findsNothing);
  });

  testWidgets('the first-ever status shows a single badge, no arrow', (
    tester,
  ) async {
    await pump(tester);

    // The seed's oldest entry (null oldStatus) renders only its new status;
    // the three transitions each render an arrow.
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(3));
  });

  testWidgets('a player with no changes sees the empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eligibilityHistoryRepositoryProvider.overrideWithValue(
            _EmptyRepository(),
          ),
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

  Future<void> openEditableHistory(
    WidgetTester tester,
    _DelayedRepository repository,
    ValueChanged<EligibilityStatus?> onSaved,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eligibilityHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<EligibilityStatus>(
                        MaterialPageRoute(
                          builder: (_) => const EligibilityHistoryScreen(
                            playerId: 'p1',
                            playerName: 'Rhobert Ronaldo',
                            currentStatus: EligibilityStatus.eligible,
                            canUpdate: true,
                          ),
                        ),
                      );
                  onSaved(result);
                },
                child: const Text('Open eligibility'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open eligibility'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Update eligibility'));
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<EligibilityStatus>), findsNWidgets(3));
    expect(find.text('Pending'), findsNothing);
    await tester.tap(find.text('Academic Warning'));
    await tester.pump();
    expect(repository.savedStatus, isNull);
    await tester.tap(find.text('Save status'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'coordinator save survives a delayed response and returns status',
    (tester) async {
      final repository = _DelayedRepository();
      EligibilityStatus? saved;
      await openEditableHistory(tester, repository, (value) => saved = value);

      expect(repository.savedPlayerId, 'p1');
      expect(repository.savedStatus, EligibilityStatus.academicWarning);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Update eligibility',
              ),
            )
            .onPressed,
        isNull,
      );
      repository.result.complete(EligibilityStatus.academicWarning);
      await tester.pumpAndSettle();

      expect(saved, EligibilityStatus.academicWarning);
      expect(find.byType(EligibilityHistoryScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed coordinator save keeps the screen open for retry', (
    tester,
  ) async {
    final repository = _DelayedRepository();
    var returned = false;
    await openEditableHistory(tester, repository, (_) => returned = true);
    repository.result.completeError(
      EligibilityHistoryRepositoryException('Could not save eligibility.'),
    );
    await tester.pumpAndSettle();

    expect(returned, isFalse);
    expect(find.byType(EligibilityHistoryScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Update eligibility',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
