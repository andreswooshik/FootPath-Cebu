import 'package:footpath_cebu/domain/entities/user_profile.dart';

/// Writes the signed-in mobile user's own profile photo through Django.
abstract class ProfilePhotoRepository {
  Future<UserProfile> uploadMyPhoto(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  });
}

class ProfilePhotoRepositoryException implements Exception {
  const ProfilePhotoRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
