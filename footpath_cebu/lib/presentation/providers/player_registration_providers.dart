import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/player_registration.dart';
import 'package:footpath_cebu/domain/repositories/player_registration_repository.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

enum RegistrationStep {
  guardianQuestion,
  existingGuardian,
  newGuardian,
  player,
  review,
  success,
}

class RegistrationState {
  RegistrationState({
    PlayerRegistrationDraft? draft,
    this.step = RegistrationStep.guardianQuestion,
    this.isBusy = false,
    this.error,
    this.duplicateGuardianId,
    this.retryOnly = false,
    this.result,
  }) : draft = draft ?? PlayerRegistrationDraft();
  final PlayerRegistrationDraft draft;
  final RegistrationStep step;
  final bool isBusy, retryOnly;
  final String? error, duplicateGuardianId;
  final PlayerRegistrationResult? result;
}

class PlayerRegistrationController extends Notifier<RegistrationState> {
  @override
  RegistrationState build() => RegistrationState();

  void _set({
    PlayerRegistrationDraft? draft,
    RegistrationStep? step,
    bool busy = false,
    String? error,
    String? duplicateGuardianId,
    bool retryOnly = false,
    PlayerRegistrationResult? result,
  }) {
    state = RegistrationState(
      draft: draft ?? state.draft,
      step: step ?? state.step,
      isBusy: busy,
      error: error,
      duplicateGuardianId: duplicateGuardianId,
      retryOnly: retryOnly,
      result: result,
    );
  }

  void chooseGuardian(bool exists) {
    if (state.isBusy || state.retryOnly) return;
    _set(
      step: exists
          ? RegistrationStep.existingGuardian
          : RegistrationStep.newGuardian,
    );
  }

  void selectGuardian(ClubMember guardian) {
    if (state.isBusy || state.retryOnly) return;
    _set(
      draft: state.draft.copyWith(existingGuardian: guardian),
      step: RegistrationStep.player,
    );
  }

  void editGuardian(GuardianRegistrationData guardian) {
    if (state.isBusy || state.retryOnly) return;
    _set(
      draft: state.draft.copyWith(
        guardian: guardian,
        clearExistingGuardian: true,
      ),
    );
  }

  void editPlayer(PlayerRegistrationData player) {
    if (state.isBusy || state.retryOnly) return;
    _set(draft: state.draft.copyWith(player: player));
  }

  Future<void> continueGuardian() async {
    if (state.isBusy) return;
    _set(busy: true);
    try {
      await ref
          .read(playerRegistrationRepositoryProvider)
          .checkGuardian(state.draft.guardian);
      if (ref.mounted) {
        _set(step: RegistrationStep.player);
      }
    } on PlayerRegistrationException catch (error) {
      if (ref.mounted) {
        _set(
          error: error.message,
          duplicateGuardianId: error.existingGuardianId,
        );
      }
    } catch (_) {
      if (ref.mounted) {
        _set(error: 'Could not check guardian details. Please retry.');
      }
    }
  }

  void review() {
    if (!state.isBusy && !state.retryOnly) {
      _set(step: RegistrationStep.review);
    }
  }

  bool back() {
    if (state.isBusy || state.retryOnly) return false;
    final previous = switch (state.step) {
      RegistrationStep.guardianQuestion || RegistrationStep.success => null,
      RegistrationStep.existingGuardian ||
      RegistrationStep.newGuardian => RegistrationStep.guardianQuestion,
      RegistrationStep.player =>
        state.draft.existingGuardian != null
            ? RegistrationStep.existingGuardian
            : RegistrationStep.newGuardian,
      RegistrationStep.review => RegistrationStep.player,
    };
    if (previous == null) return true;
    _set(step: previous);
    return false;
  }

  Future<void> submit() async {
    if (state.isBusy || state.result != null) return;
    _set(busy: true, retryOnly: state.retryOnly);
    try {
      final result = await ref
          .read(playerRegistrationRepositoryProvider)
          .register(state.draft);
      if (!ref.mounted) return;
      ref.invalidate(squadProvider);
      ref.invalidate(clubMembersProvider(ClubMemberRole.guardian));
      _set(step: RegistrationStep.success, result: result);
    } on PlayerRegistrationException catch (error) {
      if (ref.mounted) {
        _set(
          error: error.message,
          duplicateGuardianId: error.existingGuardianId,
          retryOnly: error.uncertain,
        );
      }
    } catch (_) {
      if (ref.mounted) {
        _set(
          error: 'Could not confirm registration. Retry to check its status.',
          retryOnly: true,
        );
      }
    }
  }
}

final playerRegistrationControllerProvider =
    NotifierProvider.autoDispose<
      PlayerRegistrationController,
      RegistrationState
    >(PlayerRegistrationController.new);
