import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';
import 'package:footpath_cebu/presentation/widgets/session_confirmation_button.dart';

class _FailingConfirmationRepository implements SessionConfirmationRepository {
  _FailingConfirmationRepository({this.failLoad = false});

  final bool failLoad;

  @override
  Future<List<SessionConfirmation>> fetchConfirmationsForPlayer(
    String playerId,
  ) async {
    if (failLoad) {
      throw SessionConfirmationRepositoryException('Load failed.');
    }
    return const [];
  }

  @override
  Future<SessionConfirmation> confirmSession(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) async {
    throw SessionConfirmationRepositoryException('Save failed.');
  }
}

/// Two confirm buttons for the same player but different sessions — the exact
/// setup where the shared-loading bug showed up: confirming one session used to
/// spin every card's button. Repository providers default to the in-memory
/// mocks in a test environment (see core/di/providers.dart), and the mock
/// confirmSession has a 300ms delay so the in-flight state is observable.
Widget _twoButtons() => const ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SessionConfirmationButton(sessionId: 's1', playerId: 'p1'),
          SessionConfirmationButton(sessionId: 's2', playerId: 'p1'),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('confirming one session only spins that session\'s button', (
    tester,
  ) async {
    await tester.pumpWidget(_twoButtons());
    // Let the confirmations list load (mock latency is 300ms). The loading
    // placeholder has no animation, so advance the clock explicitly rather
    // than pumpAndSettle. Both cards then show "Confirm".
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Confirm'), findsNWidgets(2));

    // Tap the first session's Confirm and advance partway through the mock's
    // 300ms latency so the submit is mid-flight.
    await tester.tap(find.text('Confirm').first);
    await tester.pump(); // apply the in-flight state
    await tester.pump(const Duration(milliseconds: 100));

    // Only the tapped card spins; the other still offers "Confirm".
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);

    // Drain the confirm completion and the follow-up refetch it triggers, so
    // no timer is left pending at teardown.
    await tester.pump(const Duration(milliseconds: 300)); // confirm finishes
    await tester.pump(const Duration(milliseconds: 350)); // refetch finishes
    await tester.pumpAndSettle();
  });

  testWidgets('submission failure is visibly reported', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionConfirmationRepositoryProvider.overrideWithValue(
            _FailingConfirmationRepository(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SessionConfirmationButton(sessionId: 's1', playerId: 'p1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not update your response. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('confirmation load failure exposes a retry action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sessionConfirmationRepositoryProvider.overrideWithValue(
            _FailingConfirmationRepository(failLoad: true),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SessionConfirmationButton(sessionId: 's1', playerId: 'p1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry RSVP'), findsOneWidget);
  });
}
