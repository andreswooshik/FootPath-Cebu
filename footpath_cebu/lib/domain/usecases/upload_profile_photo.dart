import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/profile_photo_repository.dart';

/// Validates and uploads the signed-in Coach's private profile photo.
class UploadProfilePhoto {
  const UploadProfilePhoto(this._repository);

  static const maxBytes = 25 * 1024 * 1024;
  static const supportedContentTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final ProfilePhotoRepository _repository;

  Future<UserProfile> call(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) {
    if (profile.role != 'COACH') {
      throw const ProfilePhotoRepositoryException(
        'Only Coach accounts have a coach profile photo.',
      );
    }
    if (bytes.isEmpty) {
      throw const ProfilePhotoRepositoryException('Choose a non-empty photo.');
    }
    if (bytes.length > maxBytes) {
      throw const ProfilePhotoRepositoryException(
        'Photo must be 25 MB or smaller.',
      );
    }
    final normalizedType = contentType.toLowerCase();
    if (!supportedContentTypes.contains(normalizedType)) {
      throw const ProfilePhotoRepositoryException(
        'Only JPEG, PNG, and WebP photos are allowed.',
      );
    }
    return _repository.uploadMyPhoto(
      profile,
      bytes: bytes,
      filename: filename,
      contentType: normalizedType,
    );
  }
}
