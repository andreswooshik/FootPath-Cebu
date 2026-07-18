import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/widgets/session_confirmation_button.dart';

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
  testWidgets('confirming one session only spins that session\'s button',
      (tester) async {
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
}
