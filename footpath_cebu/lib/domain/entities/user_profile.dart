/// The signed-in user's profile, as returned by GET /api/auth/me/.
///
/// Role is assigned server-side (Django is the source of truth) and is never
/// submitted by the client — see the account-provisioning workflow. This is a
/// domain entity: no UI, no I/O. Repositories return it instead of raw JSON so
/// the presentation layer stays type-safe (never `profile['role']`).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.roleDisplay,
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;

  /// Canonical wire value, always upper-case, e.g. `COACH`, `SCHOOL_STAFF`.
  final String role;

  /// Human-friendly label, e.g. `Coach`, `School Staff`.
  final String roleDisplay;

  /// Full name, falling back to the email's local part when no name is set.
  String get name {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : email.split('@').first;
  }

  /// A label safe to display even if the backend omitted `role_display`.
  String get displayRole => roleDisplay.isNotEmpty ? roleDisplay : role;

  /// True for a coach. Gates coach-only affordances such as assigning a
  /// player's position — a UX gate only. The server is the source of truth for
  /// what a role may actually write; never rely on this for authorisation.
  bool get isCoach => role == 'COACH';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      role: (json['role'] as String? ?? '').toUpperCase(),
      roleDisplay: json['role_display'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'role': role,
        'role_display': roleDisplay,
      };
}
