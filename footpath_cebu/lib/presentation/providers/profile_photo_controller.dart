import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';

class ProfilePhotoController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<UserProfile?> submit(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    state = const AsyncLoading();
    try {
      final updated = await ref.read(uploadProfilePhotoProvider)(
        profile,
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      state = const AsyncData(null);
      return updated;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}

final profilePhotoControllerProvider =
    AsyncNotifierProvider.autoDispose<ProfilePhotoController, void>(
      ProfilePhotoController.new,
    );
