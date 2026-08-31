import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';

final developmentAssessmentFormProvider = FutureProvider.autoDispose
    .family<DevelopmentAssessmentFormData, String>(
      (ref, playerId) =>
          ref.watch(getDevelopmentAssessmentFormProvider)(playerId),
    );

final playerGrowthProvider = FutureProvider.autoDispose
    .family<PlayerGrowth, GrowthQuery>(
      (ref, query) => ref.watch(growthRepositoryProvider).fetchGrowth(query),
    );
