/// The signed-in user's profile, as returned by the backend after login.
///
/// Role is assigned server-side (via Firebase custom claims) and is never
/// submitted by the client — see the account-provisioning workflow.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.avatar,
  });

  final String id;
  final String email;
  final String name;
  final String role;
  final String? avatar;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'player',
      avatar: json['avatar'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'avatar': avatar,
      };
}
