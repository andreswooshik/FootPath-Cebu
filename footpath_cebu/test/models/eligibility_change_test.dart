import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/entities/player.dart';

void main() {
  group('EligibilityChange.fromJson', () {
    test('parses the wire shape the backend serializer emits', () {
      final change = EligibilityChange.fromJson(const {
        'id': '7',
        'oldStatus': 'ELIGIBLE',
        'newStatus': 'ACADEMIC_WARNING',
        'changedAt': '2026-06-28T11:45:00+08:00',
        'changedBy': 'School Staff',
      });

      expect(change.id, '7');
      expect(change.oldStatus, EligibilityStatus.eligible);
      expect(change.newStatus, EligibilityStatus.academicWarning);
      expect(change.changedAt.year, 2026);
      expect(change.changedBy, 'School Staff');
    });

    test('an empty oldStatus means no prior value, not a default', () {
      final change = EligibilityChange.fromJson(const {
        'id': '1',
        'oldStatus': '',
        'newStatus': 'PENDING',
        'changedAt': '2026-05-04T09:30:00+08:00',
        'changedBy': 'System',
      });

      expect(change.oldStatus, isNull);
      expect(change.newStatus, EligibilityStatus.pending);
    });

    test('a missing changedBy falls back to System', () {
      final change = EligibilityChange.fromJson(const {
        'id': '2',
        'oldStatus': 'PENDING',
        'newStatus': 'ELIGIBLE',
        'changedAt': '2026-05-20T14:05:00+08:00',
      });

      expect(change.changedBy, 'System');
    });
  });

  test('toJson round-trips through fromJson', () {
    final original = EligibilityChange(
      id: '3',
      oldStatus: EligibilityStatus.academicWarning,
      newStatus: EligibilityStatus.eligible,
      changedAt: DateTime(2026, 7, 12, 10, 15),
      changedBy: 'School Staff',
    );

    final restored = EligibilityChange.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.oldStatus, original.oldStatus);
    expect(restored.newStatus, original.newStatus);
    expect(restored.changedAt, original.changedAt);
    expect(restored.changedBy, original.changedBy);
  });
}
