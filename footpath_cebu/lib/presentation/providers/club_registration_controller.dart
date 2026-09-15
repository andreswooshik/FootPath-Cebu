import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/club_registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/club_registration.dart';
import 'package:footpath_cebu/domain/repositories/club_registration_repository.dart';

class ClubRegistrationState {
  const ClubRegistrationState({
    this.license,
    this.isSubmitting = false,
    this.showPassword = false,
    this.showConfirmation = false,
    this.fieldErrors = const {},
    this.error,
  });

  final CoachLicenseUpload? license;
  final bool isSubmitting;
  final bool showPassword;
  final bool showConfirmation;
  final Map<String, String> fieldErrors;
  final String? error;

  ClubRegistrationState copyWith({
    CoachLicenseUpload? license,
    bool clearLicense = false,
    bool? isSubmitting,
    bool? showPassword,
    bool? showConfirmation,
    Map<String, String>? fieldErrors,
    String? error,
    bool clearError = false,
  }) => ClubRegistrationState(
    license: clearLicense ? null : license ?? this.license,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    showPassword: showPassword ?? this.showPassword,
    showConfirmation: showConfirmation ?? this.showConfirmation,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    error: clearError ? null : error ?? this.error,
  );
}

class ClubRegistrationController extends Notifier<ClubRegistrationState> {
  @override
  ClubRegistrationState build() => const ClubRegistrationState();

  void togglePassword() =>
      state = state.copyWith(showPassword: !state.showPassword);

  void toggleConfirmation() =>
      state = state.copyWith(showConfirmation: !state.showConfirmation);

  String? setLicense({
    required Uint8List bytes,
    required String filename,
    required String? extension,
  }) {
    final normalized = (extension ?? '').toLowerCase();
    final contentType = switch (normalized) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => null,
    };
    if (contentType == null) {
      const message = 'Only JPG, PNG, and PDF files are allowed.';
      state = state.copyWith(
        clearLicense: true,
        fieldErrors: {...state.fieldErrors, 'coach_license': message},
        clearError: true,
      );
      return message;
    }
    if (bytes.isEmpty) {
      const message = 'The selected file is empty.';
      state = state.copyWith(
        clearLicense: true,
        fieldErrors: {...state.fieldErrors, 'coach_license': message},
        clearError: true,
      );
      return message;
    }
    if (bytes.length > mobileCoachLicenseMaxBytes) {
      const message = 'File must not exceed 50 MB.';
      state = state.copyWith(
        clearLicense: true,
        fieldErrors: {...state.fieldErrors, 'coach_license': message},
        clearError: true,
      );
      return message;
    }
    final errors = {...state.fieldErrors}..remove('coach_license');
    state = state.copyWith(
      license: CoachLicenseUpload(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      ),
      fieldErrors: errors,
      clearError: true,
    );
    return null;
  }

  void setFilePickerError() {
    const message = 'The selected file could not be read.';
    state = state.copyWith(
      fieldErrors: {...state.fieldErrors, 'coach_license': message},
    );
  }

  void clearFieldError(String field) {
    if (!state.fieldErrors.containsKey(field)) return;
    final errors = {...state.fieldErrors}..remove(field);
    state = state.copyWith(fieldErrors: errors, clearError: true);
  }

  Future<ClubRegistrationResult?> submit({
    required String clubName,
    required String coordinatorName,
    required String headCoachName,
    required String cvfaMembership,
    required bool isSchoolAffiliated,
    required String schoolName,
    required String email,
    required String password,
  }) async {
    if (state.isSubmitting) return null;
    final license = state.license;
    if (license == null) {
      state = state.copyWith(
        fieldErrors: {
          ...state.fieldErrors,
          'coach_license': 'Choose a coach license file.',
        },
      );
      return null;
    }
    state = state.copyWith(
      isSubmitting: true,
      fieldErrors: const {},
      clearError: true,
    );
    try {
      final result = await ref.read(submitClubRegistrationProvider)(
        ClubRegistrationApplication(
          clubName: clubName.trim(),
          coordinatorName: coordinatorName.trim(),
          headCoachName: headCoachName.trim(),
          coachLicense: license,
          cvfaMembership: cvfaMembership.trim(),
          isSchoolAffiliated: isSchoolAffiliated,
          schoolName: isSchoolAffiliated ? schoolName.trim() : '',
          email: email.trim().toLowerCase(),
          password: password,
        ),
      );
      if (ref.mounted) state = state.copyWith(isSubmitting: false);
      return result;
    } on ClubRegistrationException catch (exception) {
      if (ref.mounted) {
        state = state.copyWith(
          isSubmitting: false,
          fieldErrors: exception.fieldErrors,
          error: exception.message,
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          isSubmitting: false,
          error: 'The application could not be submitted. Please try again.',
        );
      }
    }
    return null;
  }
}

final clubRegistrationControllerProvider =
    NotifierProvider.autoDispose<
      ClubRegistrationController,
      ClubRegistrationState
    >(ClubRegistrationController.new);
