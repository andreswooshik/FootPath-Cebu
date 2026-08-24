import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Validates and uploads a Coach-selected roster photo.
class UploadPlayerPhoto {
  const UploadPlayerPhoto(this._writer);

  static const maxBytes = 25 * 1024 * 1024;
  static const supportedContentTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final PlayerPhotoWriter _writer;

  Future<Player> call(
    String playerId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) {
    if (bytes.isEmpty) {
      throw PlayerRepositoryException('Choose a non-empty photo.');
    }
    if (bytes.length > maxBytes) {
      throw PlayerRepositoryException('Photo must be 25 MB or smaller.');
    }
    if (!supportedContentTypes.contains(contentType.toLowerCase())) {
      throw PlayerRepositoryException(
        'Only JPEG, PNG, and WebP photos are allowed.',
      );
    }
    return _writer.uploadPhoto(
      playerId,
      bytes: bytes,
      filename: filename,
      contentType: contentType.toLowerCase(),
    );
  }
}
