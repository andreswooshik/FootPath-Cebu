import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';

final tournamentSchedulesProvider =
    FutureProvider.autoDispose<List<TournamentSchedule>>((ref) {
      return ref.watch(tournamentScheduleRepositoryProvider).fetchSchedules();
    });
