import 'dart:math';

import 'package:footpath_cebu/domain/entities/club_member.dart';

class GuardianRegistrationData {
  const GuardianRegistrationData({
    this.firstName = '',
    this.middleInitial = '',
    this.lastName = '',
    this.email = '',
    this.mobileNumber = '',
  });
  final String firstName, middleInitial, lastName, email, mobileNumber;
  String get name => [
    firstName,
    if (middleInitial.isNotEmpty) '${middleInitial.replaceAll('.', '')}.',
    lastName,
  ].where((part) => part.isNotEmpty).join(' ');
  Map<String, dynamic> toJson() => {
    'firstName': firstName.trim(),
    'middleInitial': middleInitial.trim().replaceAll('.', '').toUpperCase(),
    'lastName': lastName.trim(),
    'email': email.trim().toLowerCase(),
    'mobileNumber': mobileNumber.trim(),
  };
}

class PlayerRegistrationData {
  const PlayerRegistrationData({
    this.firstName = '',
    this.lastName = '',
    this.middleInitial = '',
    this.dateOfBirth,
  });
  final String firstName, lastName, middleInitial;
  final DateTime? dateOfBirth;
  String get name => '$firstName $lastName'.trim();
  Map<String, dynamic> toJson() => {
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'middleInitial': middleInitial.trim(),
    'dateOfBirth': dateOfBirth?.toIso8601String().split('T').first,
  };
}

class PlayerRegistrationDraft {
  PlayerRegistrationDraft({
    String? requestId,
    this.player = const PlayerRegistrationData(),
    this.guardian = const GuardianRegistrationData(),
    this.existingGuardian,
  }) : requestId = requestId ?? _requestId();

  final String requestId;
  final PlayerRegistrationData player;
  final GuardianRegistrationData guardian;
  final ClubMember? existingGuardian;
  String get guardianName => existingGuardian?.name ?? guardian.name;
  String get guardianEmail => existingGuardian?.email ?? guardian.email;

  PlayerRegistrationDraft copyWith({
    PlayerRegistrationData? player,
    GuardianRegistrationData? guardian,
    ClubMember? existingGuardian,
    bool clearExistingGuardian = false,
  }) => PlayerRegistrationDraft(
    requestId: requestId,
    player: player ?? this.player,
    guardian: guardian ?? this.guardian,
    existingGuardian: clearExistingGuardian
        ? null
        : existingGuardian ?? this.existingGuardian,
  );

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'player': player.toJson(),
    if (existingGuardian != null)
      'existingGuardianId': existingGuardian!.id
    else
      'newGuardian': guardian.toJson(),
  };

  static String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class PlayerRegistrationResult {
  const PlayerRegistrationResult({
    required this.playerId,
    required this.guardianId,
    required this.coordinatorId,
    required this.guardianCreated,
    required this.guardianEmail,
    this.guardianTemporaryPassword,
    this.replayed = false,
  });
  final String playerId, guardianId, coordinatorId, guardianEmail;
  final bool guardianCreated, replayed;
  final String? guardianTemporaryPassword;

  factory PlayerRegistrationResult.fromJson(Map<String, dynamic> json) =>
      PlayerRegistrationResult(
        playerId: json['playerId'] as String,
        guardianId: json['guardianId'] as String,
        coordinatorId: json['coordinatorId'] as String,
        guardianCreated: json['guardianCreated'] as bool,
        guardianEmail: json['guardianEmail'] as String,
        guardianTemporaryPassword: json['guardianTemporaryPassword'] as String?,
        replayed: json['replayed'] as bool? ?? false,
      );
}
