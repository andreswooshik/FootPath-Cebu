import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/repositories/club_member_repository.dart';

class ApiClubMemberRepository implements ClubMemberRepository {
  ApiClubMemberRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<List<ClubMember>> fetch(ClubMemberRole role) async {
    try {
      final rows = await _api.getList('/api/club-members/?role=${role.wire}');
      return rows.map(ClubMember.fromJson).toList(growable: false);
    } on ApiException catch (error) {
      throw ClubMemberRepositoryException(error.message);
    }
  }
}

class ClubMemberRepositoryException implements Exception {
  const ClubMemberRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
