enum ClubMemberRole { coach, guardian }

extension ClubMemberRoleInfo on ClubMemberRole {
  String get wire => name.toUpperCase();
  String get label => switch (this) {
    ClubMemberRole.coach => 'Coaches',
    ClubMemberRole.guardian => 'Guardians',
  };
}

/// Privacy-limited account data for the Coordinator's club directory.
class ClubMember {
  const ClubMember({
    required this.id,
    required this.name,
    required this.role,
    required this.roleDisplay,
    required this.email,
    this.mobileNumber = '',
    this.linkedPlayers = const [],
  });

  final String id;
  final String name;
  final ClubMemberRole role;
  final String roleDisplay;
  final String email;
  final String mobileNumber;
  final List<String> linkedPlayers;

  factory ClubMember.fromJson(Map<String, dynamic> json) => ClubMember(
    id: json['id'].toString(),
    name: json['name'] as String? ?? '',
    role: (json['role'] as String? ?? '').toUpperCase() == 'GUARDIAN'
        ? ClubMemberRole.guardian
        : ClubMemberRole.coach,
    roleDisplay: json['roleDisplay'] as String? ?? '',
    email: json['email'] as String? ?? '',
    mobileNumber: json['mobileNumber'] as String? ?? '',
    linkedPlayers: (json['linkedPlayers'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
  );
}
