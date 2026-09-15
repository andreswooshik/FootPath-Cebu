import 'package:footpath_cebu/domain/entities/club_registration.dart';
import 'package:footpath_cebu/domain/repositories/club_registration_repository.dart';

class SubmitClubRegistration {
  const SubmitClubRegistration(this._repository);

  final ClubRegistrationRepository _repository;

  Future<ClubRegistrationResult> call(
    ClubRegistrationApplication application,
  ) => _repository.submit(application);
}
