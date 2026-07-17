import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';

void main() {
  group('InjuryStatus wire format', () {
    test('round-trips every status', () {
      for (final status in InjuryStatus.values) {
        expect(InjuryStatusWire.fromWire(status.wire), status);
      }
    });

    test('is case-insensitive and defaults unknown values to active', () {
      expect(InjuryStatusWire.fromWire('recovering'), InjuryStatus.recovering);
      expect(InjuryStatusWire.fromWire('BROKEN'), InjuryStatus.active);
    });
  });

  group('InjuryRecord JSON', () {
    test('fromJson reads the full wire shape', () {
      final record = InjuryRecord.fromJson(const {
        'id': '7',
        'playerId': '12',
        'description': 'Sprained ankle',
        'bodyPart': 'Left ankle',
        'status': 'RECOVERING',
        'occurredOn': '2026-07-01',
        'resolvedOn': null,
        'notes': 'Twisted on landing.',
        'createdAt': '2026-07-01T10:00:00Z',
        'updatedAt': '2026-07-02T10:00:00Z',
      });

      expect(record.id, '7');
      expect(record.playerId, '12');
      expect(record.description, 'Sprained ankle');
      expect(record.bodyPart, 'Left ankle');
      expect(record.status, InjuryStatus.recovering);
      expect(record.occurredOn, DateTime(2026, 7, 1));
      expect(record.resolvedOn, isNull);
      expect(record.notes, 'Twisted on landing.');
    });

    test('blank optional text from the backend becomes null', () {
      final record = InjuryRecord.fromJson(const {
        'id': '7',
        'playerId': '12',
        'description': 'Bruise',
        'bodyPart': '',
        'status': 'RECOVERED',
        'occurredOn': '2026-05-02',
        'resolvedOn': '2026-05-16',
        'notes': '',
      });
      expect(record.bodyPart, isNull);
      expect(record.notes, isNull);
      expect(record.resolvedOn, DateTime(2026, 5, 16));
    });

    test('toJson emits date-only dates and omits server-owned fields', () {
      final record = InjuryRecord(
        id: '7',
        playerId: '12',
        description: 'Sprained ankle',
        status: InjuryStatus.active,
        occurredOn: DateTime(2026, 7, 1),
        resolvedOn: DateTime(2026, 7, 15),
      );

      final json = record.toJson();
      expect(json['occurredOn'], '2026-07-01');
      expect(json['resolvedOn'], '2026-07-15');
      expect(json['status'], 'ACTIVE');
      expect(json['bodyPart'], '');
      expect(json['notes'], '');
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('playerId'), isFalse);
    });
  });

  test('copyWith changes only what was passed', () {
    final record = InjuryRecord(
      id: '7',
      playerId: '12',
      description: 'Sprained ankle',
      status: InjuryStatus.active,
      occurredOn: DateTime(2026, 7, 1),
    );

    final updated = record.copyWith(
      status: InjuryStatus.recovered,
      resolvedOn: DateTime(2026, 7, 15),
    );

    expect(updated.id, '7');
    expect(updated.playerId, '12');
    expect(updated.description, 'Sprained ankle');
    expect(updated.status, InjuryStatus.recovered);
    expect(updated.resolvedOn, DateTime(2026, 7, 15));
  });
}
