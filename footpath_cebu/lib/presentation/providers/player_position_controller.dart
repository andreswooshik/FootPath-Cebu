import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

/// Drives the coach's Player Position picker.
///
/// Owns only the submit state ([AsyncValue] loading/error), mirroring
/// [EditPerformanceController]; the chosen position comes from the picker.
class PlayerPositionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Assigns [position] to [playerId]. Returns the updated player on success,
  /// or null on failure (with the error in [state] for the View to show).
  /// On success the squad roster is invalidated so the position refreshes
  /// wherever it is shown.
  Future<Player?> submit(String playerId, PlayerPosition position) async {
    state = const AsyncLoading();
    try {
      final updated = await ref.read(savePlayerPositionProvider)(
        playerId,
        position,
      );
      state = const AsyncData(null);
      ref.invalidate(squadProvider);
      return updated;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final playerPositionControllerProvider =
    AsyncNotifierProvider.autoDispose<PlayerPositionController, void>(
      PlayerPositionController.new,
    );
