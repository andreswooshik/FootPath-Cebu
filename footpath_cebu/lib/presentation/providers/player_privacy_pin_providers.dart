import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';

final playerPrivacyPinStatusProvider = FutureProvider.autoDispose
    .family<PlayerPrivacyPinStatus, String>(
      (ref, playerId) => ref.watch(getPlayerPrivacyPinStatusProvider)(playerId),
    );

/// In-memory unlock state. It stores player IDs, never PIN values, and is
/// cleared when the guardian changes players or the signed-in session ends.
class PrivacyUnlockedPlayersNotifier extends Notifier<Set<String>> {
  /// Creates the initial state for this feature controller.
  @override
  Set<String> build() => <String>{};

  /// Stores the player unlock token and marks that player as unlocked in
  /// memory.
  void unlock(String playerId, String token) {
    ref.read(playerUnlockTokenStoreProvider).put(playerId, token);
    state = {...state, playerId};
  }

  /// Removes all stored unlock tokens and clears the unlocked player IDs.
  void clear() {
    ref.read(playerUnlockTokenStoreProvider).clear();
    state = <String>{};
  }
}

final privacyUnlockedPlayersProvider =
    NotifierProvider<PrivacyUnlockedPlayersNotifier, Set<String>>(
      PrivacyUnlockedPlayersNotifier.new,
    );
