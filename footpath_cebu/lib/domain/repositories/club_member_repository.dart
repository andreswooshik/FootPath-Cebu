import 'package:footpath_cebu/domain/entities/club_member.dart';

abstract interface class ClubMemberRepository {
  Future<List<ClubMember>> fetch(ClubMemberRole role);
}
