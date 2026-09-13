import 'package:footpath_cebu/domain/entities/member_registration.dart';

abstract interface class MemberRegistrationRepository {
  Future<MemberRegistrationResult> create(
    MemberAccountRole role,
    MemberRegistrationData data,
  );
}

class MemberRegistrationException implements Exception {
  const MemberRegistrationException(this.message);
  final String message;

  @override
  String toString() => message;
}
