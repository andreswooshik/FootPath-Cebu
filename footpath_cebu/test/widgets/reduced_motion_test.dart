import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/coach_overview_providers.dart';
import 'package:footpath_cebu/presentation/widgets/attribute_radar_chart.dart';
import 'package:footpath_cebu/presentation/widgets/streak_counter.dart';
import 'package:footpath_cebu/presentation/widgets/team_overview_card.dart';

void main() {
  testWidgets('progress visuals render without animation when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: const [
              TeamOverviewCard(
                overview: TeamOverview(
                  squadSize: 10,
                  readyCount: 8,
                  alerts: [],
                  nextSession: null,
                ),
              ),
              AttributeRadarChart(
                ratings: PlayerRatings(
                  pace: 80,
                  shooting: 75,
                  passing: 70,
                  dribbling: 85,
                  defending: 60,
                  physical: 72,
                ),
                isGoalkeeper: false,
                size: 180,
              ),
              StreakCounter(streak: 3, presentPercent: 80),
            ],
          ),
        ),
      ),
    );

    final animations = tester.widgetList<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animations, hasLength(3));
    expect(
      animations.every((animation) => animation.duration == Duration.zero),
      isTrue,
    );
  });
}
