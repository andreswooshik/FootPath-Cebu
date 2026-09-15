import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/data/repositories/api_club_registration_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_club_registration_repository.dart';
import 'package:footpath_cebu/domain/repositories/club_registration_repository.dart';
import 'package:footpath_cebu/domain/usecases/submit_club_registration.dart';

final clubRegistrationRepositoryProvider = Provider<ClubRegistrationRepository>(
  (ref) => useMockData
      ? MockClubRegistrationRepository()
      : ApiClubRegistrationRepository(),
);

final submitClubRegistrationProvider = Provider<SubmitClubRegistration>(
  (ref) =>
      SubmitClubRegistration(ref.watch(clubRegistrationRepositoryProvider)),
);
