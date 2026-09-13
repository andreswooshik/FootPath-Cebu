import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/data/repositories/api_club_member_repository.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';

final clubMembersProvider = FutureProvider.autoDispose
    .family<List<ClubMember>, ClubMemberRole>((ref, role) {
      if (useMockData) {
        return ref.watch(mockClubMemberRepositoryProvider).fetch(role);
      }
      return ApiClubMemberRepository().fetch(role);
    });
