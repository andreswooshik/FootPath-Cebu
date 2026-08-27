import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/providers/coach_overview_providers.dart';
import 'package:footpath_cebu/presentation/widgets/team_overview_card.dart';

Widget _app(TeamOverview overview) => MaterialApp(
  home: Scaffold(body: TeamOverviewCard(overview: overview)),
);

void main() {
  testWidgets('independent card hides clearance language and gauge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const TeamOverview(
          squadSize: 2,
          readyCount: 0,
          alerts: [],
          nextSession: null,
          academicEligibilityApplicable: false,
        ),
      ),
    );

    expect(find.text('2 players in this squad'), findsOneWidget);
    expect(find.textContaining('cleared to play'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('ready'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('school card keeps academic clearance summary', (tester) async {
    await tester.pumpWidget(
      _app(
        const TeamOverview(
          squadSize: 2,
          readyCount: 1,
          alerts: [],
          nextSession: null,
        ),
      ),
    );

    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1 of 2 cleared to play'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
