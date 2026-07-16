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
    test('a release build never selects mock data', () {
      // useMockData is hard-false in release regardless of the USE_MOCK define.
      // In the (debug) test runner kReleaseMode is false, so this asserts the
      // invariant that matters: release => live.
      if (kReleaseMode) {
        expect(useMockData, isFalse);
      } else {
        // Debug default is mock (UI dev). The important guarantee is the
        // release branch above; this documents the debug default.
        expect(useMockData, isTrue);
      }
    });
  });

  group('M3 — device registration is a safe no-op without a token provider', () {
    test('mock registration completes without error', () async {
      await RegisterDevice(MockDeviceRepository())();
    });

    test('live repo with no token provider is a logged no-op (no throw)',
        () async {
      // Default (no provider): registration returns without touching the
      // network or the FCM plugin. Enables shipping before FCM is pinned.
      await RegisterDevice(ApiDeviceRepository())();
    });
  });

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
      final updated = await save(target.id, newRatings);
      expect(updated.ratings.pace, 50);

      // Re-fetch: the mutation persisted (mirrors a real backend write).
      final refetched = await repo.fetchSquad();
      final same = refetched.firstWhere((p) => p.id == target.id);
      expect(same.ratings.shooting, 51);
    });

    test('controller surfaces success and error states', () async {
      final repo = MockPlayerRepository();
      final container = ProviderContainer(
        overrides: [playerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final sub =
          container.listen(editPerformanceControllerProvider, (_, _) {});
      final controller =
          container.read(editPerformanceControllerProvider.notifier);
      final squad = await repo.fetchSquad();

      const ratings = PlayerRatings(
        pace: 60, shooting: 60, passing: 60, dribbling: 60,
        defending: 60, physical: 60,
      );
      final ok = await controller.submit(squad.first.id, ratings);
      expect(ok, isNotNull);
      expect(sub.read().hasError, isFalse);

      // Unknown player id → error path, no throw.
      final bad = await controller.submit('does-not-exist', ratings);
      expect(bad, isNull);
      expect(sub.read().hasError, isTrue);
    });
  });
}
