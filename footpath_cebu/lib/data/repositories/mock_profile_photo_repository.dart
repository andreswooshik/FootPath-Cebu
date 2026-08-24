import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/profile_photo_repository.dart';

class MockProfilePhotoRepository implements ProfilePhotoRepository {
  @override
  Future<UserProfile> uploadMyPhoto(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    return UserProfile(
      id: profile.id,
      email: profile.email,
      firstName: profile.firstName,
      lastName: profile.lastName,
      role: profile.role,
      roleDisplay: profile.roleDisplay,
      photoUrl: 'https://example.invalid/mock-profile-photo/${profile.id}',
    );
  }
}
