import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Use case: load the signed-in player's own profile.
class GetMyProfile {
  const GetMyProfile(this._repository);

  final PlayerProfileRepository _repository;

  Future<Player> call() => _repository.fetchMyProfile();
}
