import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';

/// The signed-in player's own profile (Player dashboard). Refresh with
/// `ref.refresh(myProfileProvider.future)`.
final myProfileProvider = FutureProvider.autoDispose<Player>(
  (ref) => ref.watch(getMyProfileProvider)(),
);
