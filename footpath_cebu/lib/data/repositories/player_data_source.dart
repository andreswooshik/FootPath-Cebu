import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/repositories/development_assessment_repository.dart';

/// Full capability contract used only to assemble one shared player adapter.
abstract interface class PlayerDataSource
    implements
        PlayerRepository,
        PlayerDetailsReader,
        PlayerPhotoWriter,
        DevelopmentAssessmentRepository {}
