import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/development_assessment_repository.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

Future<List<Player>> _players(WidgetTester tester, MockPlayerRepository repo) =>
    tester.runAsync(repo.fetchSquad).then((value) => value!);

Future<void> _pump(
  WidgetTester tester,
  Player player,
  MockPlayerRepository repo,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: EditPerformanceDataScreen(player: player, profile: _coach),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    500,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _rateEverything(
  WidgetTester tester,
  DevelopmentAssessmentFormData form, {
  int value = 3,
}) async {
  for (final domain in form.framework.domains) {
    for (final indicator in domain.indicators) {
      final finder = find.byKey(
        Key('score-${domain.key}-${indicator.key}-$value'),
      );
      await _scrollTo(tester, finder);
      await tester.tap(finder);
      await tester.pump();
    }
  }
}

class _PendingRepository implements DevelopmentAssessmentRepository {
  final completer = Completer<DevelopmentAssessmentFormData>();

  @override
  Future<DevelopmentAssessmentFormData> fetchDevelopmentAssessmentForm(
    String playerId,
  ) => completer.future;

  @override
  Future<Player> saveDevelopmentAssessment(
    String playerId,
    DevelopmentAssessmentDraft draft,
  ) => throw UnimplementedError();
}

class _ErrorRepository implements DevelopmentAssessmentRepository {
  @override
  Future<DevelopmentAssessmentFormData> fetchDevelopmentAssessmentForm(
    String playerId,
  ) => Future.error(Exception('Framework unavailable.'));

  @override
  Future<Player> saveDevelopmentAssessment(
    String playerId,
    DevelopmentAssessmentDraft draft,
  ) => throw UnimplementedError();
}

void main() {
  testWidgets('shows five domains with attack-specific indicators', (
    tester,
  ) async {
    final repo = MockPlayerRepository();
    final player = (await _players(
      tester,
      repo,
    )).firstWhere((candidate) => candidate.id == 'p3');
    await _pump(tester, player, repo);

    for (final label in ['1v1 and dribbling', 'Finishing']) {
      await _scrollTo(tester, find.text(label));
      expect(find.text(label), findsOneWidget);
    }
    for (final domain in <(String, String)>[
      ('technical', 'Technical'),
      ('tactical', 'Tactical / Game Intelligence'),
      ('physical', 'Physical / Coordinative'),
      ('mental', 'Mental / Emotional'),
      ('socialValues', 'Social / Values'),
    ]) {
      final finder = find.byKey(Key('domain-${domain.$1}'));
      await _scrollTo(tester, finder);
      expect(find.text(domain.$2), findsOneWidget);
    }
    expect(find.text('Handling and shot-stopping'), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('shows goalkeeper-specific indicators', (tester) async {
    final repo = MockPlayerRepository();
    final player = (await _players(
      tester,
      repo,
    )).firstWhere((candidate) => candidate.id == 'p7');
    await _pump(tester, player, repo);

    for (final label in [
      'Handling and shot-stopping',
      'Goalkeeper distribution',
      'Goalkeeper composure',
    ]) {
      await _scrollTo(tester, find.text(label));
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Finishing'), findsNothing);
  });

  testWidgets('requires reliable observations, strength, and target', (
    tester,
  ) async {
    final repo = MockPlayerRepository();
    final player = (await _players(
      tester,
      repo,
    )).firstWhere((candidate) => candidate.id == 'p2');
    await _pump(tester, player, repo);

    await _scrollTo(
      tester,
      find.byKey(const Key('saveDevelopmentAssessmentButton')),
    );
    await tester.tap(find.byKey(const Key('saveDevelopmentAssessmentButton')));
    await tester.pump();

    expect(
      find.textContaining('Complete the required observations'),
      findsOneWidget,
    );
    expect(find.text('Add one observed strength.'), findsOneWidget);
    expect(find.text('Add one development target.'), findsOneWidget);
    expect(find.textContaining('minimum'), findsWidgets);
  });

  testWidgets('saves a complete assessment and updates the mock profile', (
    tester,
  ) async {
    final repo = MockPlayerRepository();
    final player = (await _players(
      tester,
      repo,
    )).firstWhere((candidate) => candidate.id == 'p2');
    final form = await tester.runAsync(
      () => repo.fetchDevelopmentAssessmentForm(player.id),
    );
    await _pump(tester, player, repo);
    await _rateEverything(tester, form!);

    await _scrollTo(tester, find.byKey(const Key('strengthsField')));
    await tester.enterText(
      find.byKey(const Key('strengthsField')),
      'Scans before receiving.',
    );
    await tester.enterText(
      find.byKey(const Key('developmentTargetsField')),
      'Use the weaker foot under pressure.',
    );
    await tester.enterText(
      find.byKey(const Key('coachNotesField')),
      'Good response to feedback.',
    );
    await _scrollTo(
      tester,
      find.byKey(const Key('saveDevelopmentAssessmentButton')),
    );
    await tester.tap(find.byKey(const Key('saveDevelopmentAssessmentButton')));
    await tester.pumpAndSettle();

    final updated = (await _players(
      tester,
      repo,
    )).firstWhere((candidate) => candidate.id == player.id);
    expect(updated.developmentAssessment, isNotNull);
    expect(updated.developmentAssessment!.domainScores['technical'], 3.0);
    expect(updated.developmentAssessment!.strengths, 'Scans before receiving.');
    expect(
      updated.developmentAssessment!.developmentTargets,
      'Use the weaker foot under pressure.',
    );
  });

  testWidgets('shows loading and retryable error states', (tester) async {
    final mock = MockPlayerRepository();
    final player = (await _players(tester, mock)).first;
    final pending = _PendingRepository();
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        retry: (retryCount, error) => null,
        overrides: [
          developmentAssessmentRepositoryProvider.overrideWithValue(pending),
        ],
        child: MaterialApp(
          home: EditPerformanceDataScreen(player: player, profile: _coach),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(DashboardLoadingState), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        retry: (retryCount, error) => null,
        overrides: [
          developmentAssessmentRepositoryProvider.overrideWithValue(
            _ErrorRepository(),
          ),
        ],
        child: MaterialApp(
          home: EditPerformanceDataScreen(player: player, profile: _coach),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
