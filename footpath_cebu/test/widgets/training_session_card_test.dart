import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/widgets/training_session_card.dart';

TrainingSession _session(Set<AgeTier> tiers) => TrainingSession(
      id: 't1',
      title: 'Tactical Workshop',
      ageTiers: tiers,
      date: DateTime(2026, 7, 21),
      startTime: '04:30 PM',
      endTime: '06:00 PM',
      location: 'USJ-R Basak Pitch',
      focus: SessionFocus.technical,
      attendeeCount: 12,
    );

/// Renders one card at a fixed width and returns the focus icon's right edge.
Future<double> _iconRight(WidgetTester tester, Set<AgeTier> tiers) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, child: TrainingSessionCard(session: _session(tiers))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byIcon(Icons.sports_soccer)).right;
}

void main() {
  group('TrainingSessionCard header', () {
    testWidgets('the focus icon sits in the same place for every tier label',
        (tester) async {
      // The pill's width varies a lot with the label — "FOUNDATION" is far
      // shorter than "FOUNDATION · DEVELOPMENT". The icon must not move.
      final short = await _iconRight(tester, {AgeTier.foundation});
      final long =
          await _iconRight(tester, {AgeTier.foundation, AgeTier.development});
      final all = await _iconRight(tester, AgeTier.values.toSet());

      expect(long, short);
      expect(all, short);
    });

    testWidgets('the focus icon is flush with the header padding',
        (tester) async {
      final iconRight = await _iconRight(tester, {AgeTier.foundation});
      final cardRight = tester.getRect(find.byType(TrainingSessionCard)).right;

      // 16px of header padding, and nothing else, separates the two.
      expect(cardRight - iconRight, 16);
    });
  });
}
