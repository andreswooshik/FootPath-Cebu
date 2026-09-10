import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/data/repositories/api_training_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_training_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/usecases/cancel_training_session.dart';
import 'package:footpath_cebu/domain/usecases/get_training_sessions.dart';
import 'package:footpath_cebu/domain/usecases/schedule_training_session.dart';
import 'package:footpath_cebu/domain/usecases/update_training_session.dart';

final trainingRepositoryProvider = Provider<TrainingRepository>(
  (ref) => useMockData ? MockTrainingRepository() : ApiTrainingRepository(),
);

final getTrainingSessionsProvider = Provider<GetTrainingSessions>(
  (ref) => GetTrainingSessions(ref.watch(trainingRepositoryProvider)),
);

final getTrainingSessionPageProvider = Provider<GetTrainingSessionPage>(
  (ref) => GetTrainingSessionPage(ref.watch(trainingRepositoryProvider)),
);

final scheduleTrainingSessionProvider = Provider<ScheduleTrainingSession>(
  (ref) => ScheduleTrainingSession(ref.watch(trainingRepositoryProvider)),
);

final updateTrainingSessionProvider = Provider<UpdateTrainingSession>(
  (ref) => UpdateTrainingSession(ref.watch(trainingRepositoryProvider)),
);

final cancelTrainingSessionProvider = Provider<CancelTrainingSession>(
  (ref) => CancelTrainingSession(ref.watch(trainingRepositoryProvider)),
);
