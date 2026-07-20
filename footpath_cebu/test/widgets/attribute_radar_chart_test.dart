import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/widgets/attribute_radar_chart.dart';

// The six axis labels and values are painted directly onto a Canvas via
// TextPainter inside _RadarPainter — not as Flutter Text widgets — and
// _axes/_values are file-private. So the GK-vs-outfield label *content*
// can't be asserted from an external test file; these are smoke tests
// confirming each branch builds and paints without error, plus a check that
// the public `isGoalkeeper` param is what the widget was actually given.
// Content correctness for the same GK/outfield split is covered by
// player_card_test.dart and player_profile_screen_test.dart, which render
// the same six attributes through real Text widgets.
void main() {
  group('AttributeRadarChart', () {
    testWidgets('builds for an outfield player without error', (tester) async {
      const chart = AttributeRadarChart(
        ratings: PlayerRatings(
          pace: 91, shooting: 82, passing: 73, dribbling: 64, defending: 55,
          physical: 46,
        ),
        isGoalkeeper: false,
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: chart)));
      await tester.pumpAndSettle();

      expect(find.byType(AttributeRadarChart), findsOneWidget);
      expect(
        tester.widget<AttributeRadarChart>(find.byType(AttributeRadarChart))
            .isGoalkeeper,
        isFalse,
      );
    });

    testWidgets('builds for a goalkeeper without error', (tester) async {
      const chart = AttributeRadarChart(
        ratings: PlayerRatings(
          pace: 1, shooting: 1, passing: 1, dribbling: 1, defending: 1,
          physical: 1,
          diving: 88, handling: 85, kicking: 70, reflexes: 92, speed: 62,
          positioning: 86,
        ),
        isGoalkeeper: true,
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: chart)));
      await tester.pumpAndSettle();

      expect(find.byType(AttributeRadarChart), findsOneWidget);
      expect(
        tester.widget<AttributeRadarChart>(find.byType(AttributeRadarChart))
            .isGoalkeeper,
        isTrue,
      );
    });
  });
}
