import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';

abstract class DevelopmentAssessmentRepository {
  Future<DevelopmentAssessmentFormData> fetchDevelopmentAssessmentForm(
    String playerId,
  );

  Future<Player> saveDevelopmentAssessment(
    String playerId,
    DevelopmentAssessmentDraft draft,
  );
}
