import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/api_player_registration_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_club_member_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_registration_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_registration_repository.dart';

final mockClubMemberRepositoryProvider = Provider(
  (ref) => MockClubMemberRepository(),
);

final playerRegistrationRepositoryProvider =
    Provider<PlayerRegistrationRepository>(
      (ref) => useMockData
          ? MockPlayerRegistrationRepository(
              ref.watch(mockClubMemberRepositoryProvider),
              ref.watch(playerRepositoryProvider) as MockPlayerRepository,
            )
          : ApiPlayerRegistrationRepository(),
    );
