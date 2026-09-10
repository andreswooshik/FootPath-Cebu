import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';

/// Owns the loading/error state for a Coach roster-photo upload.
class PlayerPhotoController extends MutationController {
  Future<Player?> submit(
    String playerId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    return runMutation(
      () async {
        final updated = await ref.read(uploadPlayerPhotoProvider)(
          playerId,
          bytes: bytes,
          filename: filename,
          contentType: contentType,
        );
        return updated;
      },
      onSuccess: (result) {
        ref.invalidate(squadProvider);
        ref.invalidate(myProfileProvider);
      },
    );
  }
}

final playerPhotoControllerProvider =
    AsyncNotifierProvider.autoDispose<PlayerPhotoController, void>(
      PlayerPhotoController.new,
    );
