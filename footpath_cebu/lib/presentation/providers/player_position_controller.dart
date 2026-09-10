import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

/// Drives the coach's Player Position picker.
///
/// Owns only the submit state ([AsyncValue] loading/error), mirroring
/// [EditPerformanceController]; the chosen position comes from the picker.
class PlayerPositionController extends MutationController {
  /// Assigns [position] to [playerId]. Returns the updated player on success,
  /// or null on failure (with the error in [state] for the View to show).
  /// On success the squad roster is invalidated so the position refreshes
  /// wherever it is shown.
  Future<Player?> submit(String playerId, PlayerPosition position) async {
    return runMutation(
      () async {
        final updated = await ref.read(savePlayerPositionProvider)(
          playerId,
          position,
        );
        return updated;
      },
      onSuccess: (result) {
        ref.invalidate(squadProvider);
      },
    );
  }
}

final playerPositionControllerProvider =
    AsyncNotifierProvider.autoDispose<PlayerPositionController, void>(
      PlayerPositionController.new,
    );
