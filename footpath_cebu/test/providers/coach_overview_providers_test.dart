import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/providers/coach_overview_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

const _ratings = PlayerRatings(
  pace: 10,
  shooting: 10,
  passing: 10,
  dribbling: 10,
  defending: 10,
  physical: 10,
);

Player _independentPlayer(String id, EligibilityStatus eligibility) => Player(
  id: id,
  name: 'Player $id',
  age: 12,
  classYear: 'Class of 2032',
  ageTier: AgeTier.foundation,
  ratings: _ratings,
  eligibility: eligibility,
  academicEligibilityApplicable: false,
);

void main() {
  test(
    'independent overview excludes academic readiness and grade alerts',
    () async {
      final players = [
        _independentPlayer('1', EligibilityStatus.pending),
        _independentPlayer('2', EligibilityStatus.notEligible),
      ];
      final container = ProviderContainer(
        overrides: [
          squadProvider.overrideWith((ref) async => players),
          upcomingSessionsProvider.overrideWith(
            (ref) => const AsyncData(<TrainingSession>[]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(teamOverviewProvider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(squadProvider.future);
      final overview = container.read(teamOverviewProvider).value!;

      expect(overview.academicEligibilityApplicable, isFalse);
      expect(overview.readyCount, 0);
      expect(
        overview.alerts.any((alert) => alert.title.contains('grades')),
        isFalse,
      );
      expect(
        overview.alerts.any((alert) => alert.title.contains('academic')),
        isFalse,
      );
    },
  );
}
