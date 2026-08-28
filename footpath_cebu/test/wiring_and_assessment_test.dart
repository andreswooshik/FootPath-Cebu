import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/api_device_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_device_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/usecases/register_device.dart';
import 'package:footpath_cebu/domain/usecases/save_player_assessment.dart';
import 'package:footpath_cebu/presentation/providers/edit_performance_controller.dart';

void main() {
  group('F1 — release-safe wiring', () {
    test('normal builds are live by default and tests opt into mocks', () {
      // useMockData is hard-false in release regardless of the USE_MOCK define.
      if (kReleaseMode) {
        expect(useMockData, isFalse);
      } else {
        // No build flag asks for mocks; the Flutter test process is detected
        // explicitly without changing a normal `flutter run`.
        expect(mockDataRequestedByBuild, isFalse);
        expect(useMockData, isTrue);
      }
    });
  });

  group(
    'M3 — device registration is a safe no-op without a token provider',
    () {
      test('mock registration completes without error', () async {
        await RegisterDevice(MockDeviceRepository())();
      });

      test(
        'live repo with no token provider is a logged no-op (no throw)',
        () async {
          // Default (no provider): registration returns without touching the
          // network or the FCM plugin. Enables shipping before FCM is pinned.
          await RegisterDevice(ApiDeviceRepository())();
        },
      );
    },
  );

  group('M2 — coach assessment persists through the repository', () {
    test('saveAssessment updates the roster and survives a re-fetch', () async {
      final repo = MockPlayerRepository();
      final squad = await repo.fetchSquad();
      final target = squad.first;
      final newRatings = PlayerRatings(
        pace: 50,
        shooting: 51,
        passing: 52,
        dribbling: 53,
        defending: 54,
        physical: 55,
      );

      final save = SavePlayerAssessment(repo);
      final updated = await save(
        target.id,
        newRatings,
        coachNotes: 'Excellent movement off the ball.',
      );
      expect(updated.ratings.pace, 50);

      // Re-fetch: the mutation persisted (mirrors a real backend write).
      final refetched = await repo.fetchSquad();
      final same = refetched.firstWhere((p) => p.id == target.id);
      expect(same.ratings.shooting, 51);
    });

    test('the coach note is persisted, not silently dropped', () async {
      // Regression guard: the assessment form once rendered a notes field that
      // no layer carried, so every note a coach typed was discarded on save.
      final repo = MockPlayerRepository();
      final target = (await repo.fetchSquad()).first;
      const ratings = PlayerRatings(
        pace: 70,
        shooting: 70,
        passing: 70,
        dribbling: 70,
        defending: 70,
        physical: 70,
      );

      final save = SavePlayerAssessment(repo);
      final updated = await save(
        target.id,
        ratings,
        coachNotes: 'Needs to scan before receiving.',
      );
      expect(updated.coachNotes, 'Needs to scan before receiving.');

      // And it survives a re-fetch, like the ratings do.
      final refetched = await repo.fetchSquad();
      final same = refetched.firstWhere((p) => p.id == target.id);
      expect(same.coachNotes, 'Needs to scan before receiving.');
    });

    test('a note round-trips through Player JSON', () async {
      // The wire contract is what the Django serializer emits; if `coachNotes`
      // were dropped from fromJson/toJson the note would vanish on reload.
      final target = (await MockPlayerRepository().fetchSquad()).first;
      final withNote = target.copyWith(coachNotes: 'Composed under pressure.');
      final restored = Player.fromJson(withNote.toJson());
      expect(restored.coachNotes, 'Composed under pressure.');
    });

    test('controller surfaces success and error states', () async {
      final repo = MockPlayerRepository();
      final container = ProviderContainer(
        overrides: [playerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        editPerformanceControllerProvider,
        (_, _) {},
      );
      final controller = container.read(
        editPerformanceControllerProvider.notifier,
      );
      final squad = await repo.fetchSquad();

      const ratings = PlayerRatings(
        pace: 60,
        shooting: 60,
        passing: 60,
        dribbling: 60,
        defending: 60,
        physical: 60,
      );
      final ok = await controller.submit(
        squad.first.id,
        ratings,
        coachNotes: 'Strong session.',
      );
      expect(ok, isNotNull);
      expect(ok!.coachNotes, 'Strong session.');
      expect(sub.read().hasError, isFalse);

      // Unknown player id → error path, no throw.
      final bad = await controller.submit(
        'does-not-exist',
        ratings,
        coachNotes: '',
      );
      expect(bad, isNull);
      expect(sub.read().hasError, isTrue);
    });
  });
}
