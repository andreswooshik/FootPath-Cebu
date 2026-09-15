import 'dart:typed_data';

const int mobileCoachLicenseMaxBytes = 50 * 1024 * 1024;

class CoachLicenseUpload {
  const CoachLicenseUpload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

class ClubRegistrationApplication {
  const ClubRegistrationApplication({
    required this.clubName,
    required this.coordinatorName,
    required this.headCoachName,
    required this.coachLicense,
    required this.cvfaMembership,
    required this.isSchoolAffiliated,
    required this.schoolName,
    required this.email,
    required this.password,
  });

  final String clubName;
  final String coordinatorName;
  final String headCoachName;
  final CoachLicenseUpload coachLicense;
  final String cvfaMembership;
  final bool isSchoolAffiliated;
  final String schoolName;
  final String email;
  final String password;
}

class ClubRegistrationResult {
  const ClubRegistrationResult({
    required this.status,
    required this.coordinatorEmail,
  });

  final String status;
  final String coordinatorEmail;
}
