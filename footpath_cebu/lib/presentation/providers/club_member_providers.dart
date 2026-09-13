import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';

final clubMembersProvider = FutureProvider.autoDispose
    .family<List<ClubMember>, ClubMemberRole>((ref, role) {
      return ref.watch(clubMemberRepositoryProvider).fetch(role);
    });
