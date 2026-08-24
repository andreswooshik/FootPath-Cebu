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
  @override
  Set<String> build() => <String>{};

  void unlock(String playerId, String token) {
    ref.read(playerUnlockTokenStoreProvider).put(playerId, token);
    state = {...state, playerId};
  }

  void clear() {
    ref.read(playerUnlockTokenStoreProvider).clear();
    state = <String>{};
  }
}

final privacyUnlockedPlayersProvider =
    NotifierProvider<PrivacyUnlockedPlayersNotifier, Set<String>>(
      PrivacyUnlockedPlayersNotifier.new,
    );
