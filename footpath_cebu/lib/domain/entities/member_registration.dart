import 'dart:math';

enum MemberAccountRole {
  guardian('GUARDIAN', 'Guardian'),
  coach('COACH', 'Coach');

  const MemberAccountRole(this.wire, this.label);
  final String wire;
  final String label;
}

class MemberRegistrationData {
  MemberRegistrationData({
    String? requestId,
    this.firstName = '',
    this.middleInitial = '',
    this.lastName = '',
    this.email = '',
    this.mobileNumber = '',
  }) : requestId = requestId ?? newRegistrationRequestId();

  final String requestId;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String email;
  final String mobileNumber;

  String get name => [
    firstName,
    if (middleInitial.isNotEmpty) '${middleInitial.replaceAll('.', '')}.',
    lastName,
  ].where((part) => part.isNotEmpty).join(' ');

  Map<String, dynamic> toJson(MemberAccountRole role) => {
    'requestId': requestId,
    'role': role.wire,
    'firstName': firstName.trim(),
    'middleInitial': middleInitial.trim().replaceAll('.', '').toUpperCase(),
    'lastName': lastName.trim(),
    'email': email.trim().toLowerCase(),
    'mobileNumber': mobileNumber.trim(),
  };
}

class MemberRegistrationResult {
  const MemberRegistrationResult({
    required this.memberId,
    required this.coordinatorId,
    required this.role,
    required this.name,
    required this.email,
    this.temporaryPassword,
    this.replayed = false,
  });

  final String memberId;
  final String coordinatorId;
  final MemberAccountRole role;
  final String name;
  final String email;
  final String? temporaryPassword;
  final bool replayed;

  factory MemberRegistrationResult.fromJson(Map<String, dynamic> json) =>
      MemberRegistrationResult(
        memberId: json['memberId'].toString(),
        coordinatorId: json['coordinatorId'].toString(),
        role: json['role'] == 'COACH'
            ? MemberAccountRole.coach
            : MemberAccountRole.guardian,
        name: json['name'] as String,
        email: json['email'] as String,
        temporaryPassword: json['temporaryPassword'] as String?,
        replayed: json['replayed'] as bool? ?? false,
      );
}

String newRegistrationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
