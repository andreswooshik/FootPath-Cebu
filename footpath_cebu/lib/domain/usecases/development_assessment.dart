import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/development_assessment_repository.dart';

class GetDevelopmentAssessmentForm {
  const GetDevelopmentAssessmentForm(this._repository);

  final DevelopmentAssessmentRepository _repository;

  Future<DevelopmentAssessmentFormData> call(String playerId) =>
      _repository.fetchDevelopmentAssessmentForm(playerId);
}

class SaveDevelopmentAssessment {
  const SaveDevelopmentAssessment(this._repository);

  final DevelopmentAssessmentRepository _repository;

  Future<Player> call(String playerId, DevelopmentAssessmentDraft draft) =>
      _repository.saveDevelopmentAssessment(playerId, draft);
}
