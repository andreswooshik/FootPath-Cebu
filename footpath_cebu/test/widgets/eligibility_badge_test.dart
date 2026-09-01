import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/widgets/eligibility_badge.dart';

void main() {
  test('eligibility messages expose status only', () {
    expect(
      eligibilityStatusMessage(EligibilityStatus.eligible),
      'Eligible to play',
    );
    expect(
      eligibilityStatusMessage(EligibilityStatus.notEligible),
      'Not currently eligible to play',
    );
    expect(
      eligibilityStatusMessage(EligibilityStatus.pending),
      'Awaiting eligibility clearance',
    );
    expect(
      eligibilityStatusMessage(EligibilityStatus.academicWarning),
      'Academic eligibility warning',
    );

    final allMessages = EligibilityStatus.values
        .map(eligibilityStatusMessage)
        .join(' ');
    expect(
      allMessages,
      isNot(
        contains(
          RegExp(r'grade|GPA|subject|report card', caseSensitive: false),
        ),
      ),
    );
  });
}
