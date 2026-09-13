enum CoordinatorPersonRole { player, guardian, coach }

extension CoordinatorPersonRoleInfo on CoordinatorPersonRole {
  String get path => switch (this) {
    CoordinatorPersonRole.player => 'players',
    CoordinatorPersonRole.guardian => 'guardians',
    CoordinatorPersonRole.coach => 'coaches',
  };

  String get label => switch (this) {
    CoordinatorPersonRole.player => 'Player',
    CoordinatorPersonRole.guardian => 'Guardian',
    CoordinatorPersonRole.coach => 'Coach',
  };
}

class CoordinatorPersonReference {
  const CoordinatorPersonReference({
    required this.id,
    required this.name,
    this.email = '',
    this.mobileNumber = '',
  });

  final String id;
  final String name;
  final String email;
  final String mobileNumber;

  factory CoordinatorPersonReference.fromJson(Map<String, dynamic> json) =>
      CoordinatorPersonReference(
        id: json['id'].toString(),
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        mobileNumber: json['mobileNumber'] as String? ?? '',
      );
}

class CoordinatorPersonDetails {
  const CoordinatorPersonDetails({
    required this.id,
    required this.role,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.name,
    required this.email,
    required this.mobileNumber,
    this.dateOfBirth,
    this.age,
    this.classYear = '',
    this.ageTier = '',
    this.ageTierDisplay = '',
    this.position,
    this.linkedPeople = const [],
  });

  final String id;
  final CoordinatorPersonRole role;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String name;
  final String email;
  final String mobileNumber;
  final DateTime? dateOfBirth;
  final int? age;
  final String classYear;
  final String ageTier;
  final String ageTierDisplay;
  final String? position;
  final List<CoordinatorPersonReference> linkedPeople;

  factory CoordinatorPersonDetails.fromJson(Map<String, dynamic> json) {
    final role = switch ((json['role'] as String? ?? '').toUpperCase()) {
      'GUARDIAN' => CoordinatorPersonRole.guardian,
      'COACH' => CoordinatorPersonRole.coach,
      _ => CoordinatorPersonRole.player,
    };
    return CoordinatorPersonDetails(
      id: json['id'].toString(),
      role: role,
      firstName: json['firstName'] as String? ?? '',
      middleInitial: json['middleInitial'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      mobileNumber: json['mobileNumber'] as String? ?? '',
      dateOfBirth: DateTime.tryParse(json['dateOfBirth'] as String? ?? ''),
      age: json['age'] as int?,
      classYear: json['classYear'] as String? ?? '',
      ageTier: json['ageTier'] as String? ?? '',
      ageTierDisplay: json['ageTierDisplay'] as String? ?? '',
      position: json['position'] as String?,
      linkedPeople: (json['linkedPeople'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CoordinatorPersonReference.fromJson)
          .toList(growable: false),
    );
  }
}
