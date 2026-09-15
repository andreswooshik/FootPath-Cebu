import 'package:footpath_cebu/domain/entities/club_registration.dart';
import 'package:footpath_cebu/domain/repositories/club_registration_repository.dart';

class MockClubRegistrationRepository implements ClubRegistrationRepository {
  @override
  Future<ClubRegistrationResult> submit(
    ClubRegistrationApplication application,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return ClubRegistrationResult(
      status: 'PENDING',
      coordinatorEmail: application.email,
    );
  }
}
