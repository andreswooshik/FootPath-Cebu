import 'package:footpath_cebu/domain/entities/club_registration.dart';

abstract class ClubRegistrationRepository {
  Future<ClubRegistrationResult> submit(
    ClubRegistrationApplication application,
  );
}

class ClubRegistrationException implements Exception {
  const ClubRegistrationException(this.message, {this.fieldErrors = const {}});

  final String message;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}
