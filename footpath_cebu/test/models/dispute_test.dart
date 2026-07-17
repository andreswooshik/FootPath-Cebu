import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';

void main() {
  group('wire formats', () {
    test('categories round-trip', () {
      for (final category in DisputeCategory.values) {
        expect(DisputeCategoryWire.fromWire(category.wire), category);
      }
      expect(DisputeCategoryWire.fromWire('VIBES'), DisputeCategory.other);
    });

    test('statuses round-trip, including the snake-case UNDER_REVIEW', () {
      for (final status in DisputeStatus.values) {
        expect(DisputeStatusWire.fromWire(status.wire), status);
      }
      expect(DisputeStatus.underReview.wire, 'UNDER_REVIEW');
      expect(DisputeStatusWire.fromWire('nonsense'), DisputeStatus.open);
    });
  });

  test('Dispute.fromJson reads the full wire shape with its thread', () {
    final dispute = Dispute.fromJson(const {
      'id': '3',
      'raisedByName': 'Coach Cruz',
      'subjectPlayerId': '12',
      'subjectPlayerName': 'Rhobert Ronaldo',
      'category': 'ATTENDANCE',
      'status': 'UNDER_REVIEW',
      'summary': 'Attendance mark disputed',
      'detail': 'Player claims present on July 10.',
      'createdAt': '2026-07-11T09:00:00Z',
      'updatedAt': '2026-07-12T14:00:00Z',
      'responses': [
        {
          'id': '9',
          'authorName': 'Staff Reyes',
          'authorRole': 'SCHOOL_STAFF',
          'body': 'Checking the sign-in sheet.',
          'statusChangeTo': 'UNDER_REVIEW',
          'createdAt': '2026-07-12T14:00:00Z',
        },
      ],
    });

    expect(dispute.id, '3');
    expect(dispute.category, DisputeCategory.attendance);
    expect(dispute.status, DisputeStatus.underReview);
    expect(dispute.subjectPlayerId, '12');
    expect(dispute.raisedByName, 'Coach Cruz');
    expect(dispute.responses, hasLength(1));
    final response = dispute.responses.single;
    expect(response.authorRole, 'SCHOOL_STAFF');
    expect(response.statusChangeTo, DisputeStatus.underReview);
  });

  test('blank detail and missing thread parse as null/empty', () {
    final dispute = Dispute.fromJson(const {
      'id': '4',
      'raisedByName': null,
      'subjectPlayerId': null,
      'subjectPlayerName': null,
      'category': 'OTHER',
      'status': 'OPEN',
      'summary': 'General issue',
      'detail': '',
      'createdAt': '2026-07-11T09:00:00Z',
      'updatedAt': '2026-07-11T09:00:00Z',
    });
    expect(dispute.detail, isNull);
    expect(dispute.subjectPlayerId, isNull);
    expect(dispute.responses, isEmpty);
  });
}
