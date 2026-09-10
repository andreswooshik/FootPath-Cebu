import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/security/player_unlock_token_store.dart';

final playerUnlockTokenStoreProvider = Provider<PlayerUnlockTokenStore>(
  (ref) => PlayerUnlockTokenStore(),
);
