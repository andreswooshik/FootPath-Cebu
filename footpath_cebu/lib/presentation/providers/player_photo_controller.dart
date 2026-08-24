import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';

/// Owns the loading/error state for a Coach roster-photo upload.
class PlayerPhotoController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Player?> submit(
    String playerId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    state = const AsyncLoading();
    try {
      final updated = await ref.read(uploadPlayerPhotoProvider)(
        playerId,
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      state = const AsyncData(null);
      ref.invalidate(squadProvider);
      ref.invalidate(myProfileProvider);
      return updated;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}

final playerPhotoControllerProvider =
    AsyncNotifierProvider.autoDispose<PlayerPhotoController, void>(
      PlayerPhotoController.new,
    );
