import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';

class ProfilePhotoController extends MutationController {
  Future<UserProfile?> submit(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    return runMutation(() async {
      final updated = await ref.read(uploadProfilePhotoProvider)(
        profile,
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      return updated;
    });
  }
}

final profilePhotoControllerProvider =
    AsyncNotifierProvider.autoDispose<ProfilePhotoController, void>(
      ProfilePhotoController.new,
    );
