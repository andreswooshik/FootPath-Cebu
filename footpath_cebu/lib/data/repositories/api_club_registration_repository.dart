import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/club_registration.dart';
import 'package:footpath_cebu/domain/repositories/club_registration_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClubRegistrationRepository implements ClubRegistrationRepository {
  ApiClubRegistrationRepository({
    http.Client? client,
    this.timeout = const Duration(minutes: 2),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<ClubRegistrationResult> submit(
    ClubRegistrationApplication application,
  ) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${ApiConfig.baseUrl}/api/public/club-registrations/'),
          )
          ..followRedirects = false
          ..fields.addAll({
            'club_name': application.clubName,
            'coordinator_name': application.coordinatorName,
            'head_coach_name': application.headCoachName,
            'cvfa_membership': application.cvfaMembership,
            'is_school_affiliated': application.isSchoolAffiliated ? 'on' : '',
            'school_name': application.schoolName,
            'email': application.email,
            'password1': application.password,
            'password2': application.password,
          })
          ..files.add(
            http.MultipartFile.fromBytes(
              'coach_license',
              application.coachLicense.bytes,
              filename: application.coachLicense.filename,
              contentType: MediaType.parse(
                application.coachLicense.contentType,
              ),
            ),
          );

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
    } on TimeoutException {
      throw const ClubRegistrationException(
        'The server took too long to respond. Please try again.',
      );
    } on SocketException {
      throw const ClubRegistrationException(
        'Could not reach the server. Check your connection.',
      );
    } on HandshakeException {
      throw const ClubRegistrationException(
        'Could not establish a secure server connection.',
      );
    } on http.ClientException {
      throw const ClubRegistrationException(
        'Could not reach the server. Check your connection.',
      );
    }

    final payload = _decode(response.body);
    if (response.statusCode != 201) {
      final fieldErrors = _fieldErrors(payload['errors']);
      throw ClubRegistrationException(
        fieldErrors['__all__'] ??
            fieldErrors.values.firstOrNull ??
            'The application could not be submitted.',
        fieldErrors: fieldErrors,
      );
    }
    final status = payload['status'];
    final email = payload['coordinator_email'];
    if (status is! String || email is! String) {
      throw const ClubRegistrationException(
        'The server returned an invalid application result.',
      );
    }
    return ClubRegistrationResult(status: status, coordinatorEmail: email);
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  Map<String, String> _fieldErrors(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String &&
            entry.value is List &&
            entry.value.isNotEmpty)
          entry.key as String: entry.value.first.toString(),
    };
  }
}
