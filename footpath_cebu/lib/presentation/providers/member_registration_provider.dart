import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/domain/repositories/member_registration_repository.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';

class MemberRegistrationState {
  const MemberRegistrationState({this.isBusy = false, this.error, this.result});

  final bool isBusy;
  final String? error;
  final MemberRegistrationResult? result;
}

class MemberRegistrationController extends Notifier<MemberRegistrationState> {
  @override
  MemberRegistrationState build() => const MemberRegistrationState();

  void reset() => state = const MemberRegistrationState();

  Future<void> submit(
    MemberAccountRole role,
    MemberRegistrationData data,
  ) async {
    if (state.isBusy || state.result != null) return;
    state = const MemberRegistrationState(isBusy: true);
    try {
      final result = await ref
          .read(memberRegistrationRepositoryProvider)
          .create(role, data);
      if (!ref.mounted) return;
      ref.invalidate(
        clubMembersProvider(
          role == MemberAccountRole.coach
              ? ClubMemberRole.coach
              : ClubMemberRole.guardian,
        ),
      );
      state = MemberRegistrationState(result: result);
    } on MemberRegistrationException catch (error) {
      if (ref.mounted) state = MemberRegistrationState(error: error.message);
    } catch (_) {
      if (ref.mounted) {
        state = const MemberRegistrationState(
          error: 'Could not create the account. Please retry.',
        );
      }
    }
  }
}

final memberRegistrationControllerProvider =
    NotifierProvider.autoDispose<
      MemberRegistrationController,
      MemberRegistrationState
    >(MemberRegistrationController.new);
