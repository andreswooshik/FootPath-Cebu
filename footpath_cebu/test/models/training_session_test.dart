import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';

TrainingSession _session(Set<AgeTier> tiers, {DateTime? date}) =>
    TrainingSession(
      id: 't1',
      title: 'Tactical Workshop',
      ageTiers: tiers,
      date: date ?? DateTime(2026, 3, 1),
      startTime: '04:30 PM',
      endTime: '06:00 PM',
      location: 'USJ-R Basak Pitch',
      focus: SessionFocus.technical,
    );

void main() {
  group('TrainingSession age tiers', () {
    test('orderedTiers is canonical, not tap order', () {
      final session = _session({AgeTier.pathway, AgeTier.foundation});
      expect(session.orderedTiers, [AgeTier.foundation, AgeTier.pathway]);
    });

    test('isAllTiers only when every tier is targeted', () {
      expect(_session(AgeTier.values.toSet()).isAllTiers, isTrue);
      expect(
        _session({AgeTier.foundation, AgeTier.pathway}).isAllTiers,
        isFalse,
      );
      expect(_session({AgeTier.foundation}).isAllTiers, isFalse);
    });

    test('includesTier gates attendance to the chosen tiers', () {
      final session = _session({AgeTier.foundation, AgeTier.development});
      expect(session.includesTier(AgeTier.foundation), isTrue);
      expect(session.includesTier(AgeTier.development), isTrue);
      expect(session.includesTier(AgeTier.pathway), isFalse);
    });

    test('isToday only matches the current calendar day', () {
      final now = DateTime.now();
      final today = _session({
        AgeTier.foundation,
      }, date: DateTime(now.year, now.month, now.day));
      final tomorrow = _session({
        AgeTier.foundation,
      }, date: DateTime(now.year, now.month, now.day + 1));
      expect(today.isToday, isTrue);
      expect(tomorrow.isToday, isFalse);
    });

    test('scheduledEndAt parses the local 12-hour end time', () {
      final afternoon = _session({
        AgeTier.foundation,
      }, date: DateTime(2026, 9, 1));
      final midnight = TrainingSession(
        id: 'midnight',
        title: 'Midnight recovery',
        ageTiers: const {AgeTier.foundation},
        date: DateTime(2026, 9, 1),
        startTime: '12:00 AM',
        endTime: '12:30 AM',
        location: 'Gym',
        focus: SessionFocus.physical,
      );

      expect(afternoon.scheduledEndAt, DateTime(2026, 9, 1, 18));
      expect(midnight.scheduledEndAt, DateTime(2026, 9, 1, 0, 30));
    });

    test('a session becomes past at its end time, not at midnight', () {
      final session = _session({
        AgeTier.foundation,
      }, date: DateTime(2026, 9, 1));

      expect(session.hasEndedAt(DateTime(2026, 9, 1, 17, 59)), isFalse);
      expect(session.hasEndedAt(DateTime(2026, 9, 1, 18)), isTrue);
      expect(session.hasEndedAt(DateTime(2026, 9, 1, 22, 56)), isTrue);
    });

    test('completed and cancelled sessions are historical immediately', () {
      TrainingSession withStatus(TrainingSessionStatus status) =>
          TrainingSession(
            id: status.name,
            title: status.label,
            ageTiers: const {AgeTier.foundation},
            date: DateTime(2026, 9, 2),
            startTime: '04:30 PM',
            endTime: '06:00 PM',
            location: 'Pitch',
            focus: SessionFocus.technical,
            status: status,
          );

      final now = DateTime(2026, 9, 1, 10);
      expect(
        withStatus(TrainingSessionStatus.completed).hasEndedAt(now),
        isTrue,
      );
      expect(
        withStatus(TrainingSessionStatus.cancelled).hasEndedAt(now),
        isTrue,
      );
    });

    test('a multi-tier selection round-trips through JSON', () {
      final session = _session({AgeTier.pathway, AgeTier.foundation});
      final restored = TrainingSession.fromJson(session.toJson());
      expect(restored.ageTiers, session.ageTiers);
    });

    test('toJson writes tiers as an ordered wire list', () {
      final json = _session({AgeTier.pathway, AgeTier.foundation}).toJson();
      expect(json['ageTiers'], ['FOUNDATION', 'PATHWAY']);
    });

    test('a missing or empty tier list falls back to every tier', () {
      final missing = TrainingSession.fromJson({'id': 1, 'title': 'x'});
      expect(missing.ageTiers, AgeTier.values.toSet());

      final empty = TrainingSession.fromJson({
        'id': 1,
        'title': 'x',
        'ageTiers': <String>[],
      });
      expect(empty.ageTiers, AgeTier.values.toSet());
    });
  });
}
