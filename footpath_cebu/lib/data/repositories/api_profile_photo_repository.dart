import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/profile_photo_repository.dart';

class ApiProfilePhotoRepository implements ProfilePhotoRepository {
  ApiProfilePhotoRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<UserProfile> uploadMyPhoto(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    try {
      final response = await _api.postMultipart(
        '/api/auth/me/photo/',
        fieldName: 'photo',
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      return UserProfile.fromJson(Map<String, dynamic>.from(decoded));
    } on ApiException catch (error) {
      throw ProfilePhotoRepositoryException(error.message);
    } on FormatException {
      throw const ProfilePhotoRepositoryException(
        'The server returned an invalid account profile.',
      );
    } on TypeError {
      throw const ProfilePhotoRepositoryException(
        'The server returned an invalid account profile.',
      );
    }
  }
}
