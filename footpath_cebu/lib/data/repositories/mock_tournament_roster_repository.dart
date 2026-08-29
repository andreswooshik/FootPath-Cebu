import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/repositories/tournament_roster_repository.dart';

class MockTournamentRosterRepository implements TournamentRosterRepository {
  TournamentSquad _squad = const TournamentSquad(
    id: 'squad-1',
    bracketId: 'bracket-1',
    status: TournamentSquadStatus.draft,
    entries: [],
  );

  final List<TournamentRosterCandidate> _candidates = const [
    TournamentRosterCandidate(
      playerId: '1',
      playerName: 'Alex Santos',
      currentPosition: 'CM',
      eligibility: TournamentCandidateEligibility.eligible,
      eligibilityCode: 'ELIGIBLE',
      eligibilityReason: 'Eligible for this bracket.',
      selected: false,
      tournamentPosition: '',
    ),
    TournamentRosterCandidate(
      playerId: '2',
      playerName: 'Jamie Cruz',
      currentPosition: 'ST',
      eligibility: TournamentCandidateEligibility.warning,
      eligibilityCode: 'PENDING_INJURY',
      eligibilityReason: 'Pending injury report - review before selection.',
      selected: false,
      tournamentPosition: '',
    ),
    TournamentRosterCandidate(
      playerId: '3',
      playerName: 'Sam Reyes',
      currentPosition: 'GK',
      eligibility: TournamentCandidateEligibility.blocked,
      eligibilityCode: 'OVERAGE',
      eligibilityReason: 'Overage for this bracket.',
      selected: false,
      tournamentPosition: '',
    ),
  ];

  @override
  Future<List<TournamentRosterCandidate>> fetchCandidates(
    String bracketId,
  ) async => _candidates;

  @override
  Future<TournamentSquad> fetchSquad(String bracketId) async => _squad;

  @override
  Future<TournamentSquad> saveSquad(
    String bracketId,
    List<TournamentRosterSelection> entries,
  ) async {
    _squad = TournamentSquad(
      id: _squad.id,
      bracketId: bracketId,
      status: _squad.status,
      publishedAt: _squad.publishedAt,
      entries: entries
          .map((selection) {
            final player = _candidates.firstWhere(
              (candidate) => candidate.playerId == selection.playerId,
            );
            return TournamentSquadEntry(
              id: 'entry-${selection.playerId}',
              playerId: selection.playerId,
              playerName: player.playerName,
              tournamentPosition: selection.position,
              availability: player.eligibility.name.toUpperCase(),
              availabilityReason: player.eligibilityReason,
            );
          })
          .toList(growable: false),
    );
    return _squad;
  }

  @override
  Future<TournamentSquad> publishSquad(String bracketId) async {
    _squad = TournamentSquad(
      id: _squad.id,
      bracketId: bracketId,
      status: TournamentSquadStatus.published,
      publishedAt: DateTime.now(),
      entries: _squad.entries,
    );
    return _squad;
  }
}
