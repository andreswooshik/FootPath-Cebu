import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/presentation/screens/schedule_tab_screen.dart';

const _player = Player(
  id: 'p1',
  name: 'Test Player',
  age: 14,
  classYear: 'Class of 2030',
  ageTier: AgeTier.development,
  ratings: PlayerRatings(
    pace: 70,
    shooting: 70,
    passing: 70,
    dribbling: 70,
    defending: 70,
    physical: 70,
  ),
  eligibility: EligibilityStatus.eligible,
);

class _TodayTrainingRepository implements TrainingRepository {
  @override
  Future<List<TrainingSession>> fetchSessions() async {
    final now = DateTime.now();
    return [
      TrainingSession(
        id: 'today-session',
        title: 'Shooting',
        ageTiers: const {AgeTier.development},
        date: DateTime(now.year, now.month, now.day),
        startTime: '03:30 PM',
        endTime: '06:30 PM',
        location: 'Dynamic Herb',
        focus: SessionFocus.technical,
      ),
    ];
  }

  @override
  Future<TrainingSession> createSession(TrainingSession draft) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSession(String id) => throw UnimplementedError();

  @override
  Future<TrainingSession> updateSession(TrainingSession session) =>
      throw UnimplementedError();
}

Future<void> _pumpSchedule(
  WidgetTester tester, {
  required bool isGuardian,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoryProvider.overrideWithValue(
          _TodayTrainingRepository(),
        ),
      ],
      child: MaterialApp(
        home: ScheduleTabScreen(player: _player, isGuardian: isGuardian),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('player schedule is read-only even for today\'s session', (
    tester,
  ) async {
    await _pumpSchedule(tester, isGuardian: false);

    expect(find.text('Shooting'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
    expect(find.text('Confirmed'), findsNothing);
  });

  testWidgets('guardian schedule never offers a player response action', (
    tester,
  ) async {
    await _pumpSchedule(tester, isGuardian: true);

    expect(find.text('Shooting'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
    expect(find.text('Confirmed'), findsNothing);
  });
}
