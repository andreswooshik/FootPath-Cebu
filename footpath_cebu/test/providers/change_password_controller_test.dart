import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/presentation/providers/auth_controllers.dart';

/// Records the arguments changePassword was called with, and optionally
/// throws, so tests can assert both the wiring and the error paths.
class _RecordingAuthRepo implements AuthRepository {
  String? lastCurrent;
  String? lastNew;
  Object? throwOnChange;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    lastCurrent = currentPassword;
    lastNew = newPassword;
    final e = throwOnChange;
    if (e != null) throw e;
  }

  @override
  Future<UserProfile> signInAndFetchProfile({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}
}

void main() {
  late _RecordingAuthRepo repo;

  ProviderContainer makeContainer() {
    repo = _RecordingAuthRepo();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose controller alive across awaits.
    container.listen(changePasswordControllerProvider, (_, _) {});
    return container;
  }

  test('a valid submit reaches the repository and reports success', () async {
    final container = makeContainer();

    final ok = await container
        .read(changePasswordControllerProvider.notifier)
        .submit(
          currentPassword: 'old-secret-1',
          newPassword: 'new-secret-1',
          confirmPassword: 'new-secret-1',
        );

    expect(ok, isTrue);
    expect(repo.lastCurrent, 'old-secret-1');
    expect(repo.lastNew, 'new-secret-1');
    expect(container.read(changePasswordControllerProvider).error, isNull);
  });

  group('validation stops the call before the repository', () {
    Future<String?> submitExpectingRejection({
      required ProviderContainer container,
      required String current,
      required String next,
      required String confirm,
    }) async {
      final ok = await container
          .read(changePasswordControllerProvider.notifier)
          .submit(
            currentPassword: current,
            newPassword: next,
            confirmPassword: confirm,
          );
      expect(ok, isFalse);
      expect(repo.lastCurrent, isNull, reason: 'repo must not be called');
      return container.read(changePasswordControllerProvider).error;
    }

    test('empty current password', () async {
      final error = await submitExpectingRejection(
        container: makeContainer(),
        current: '',
        next: 'new-secret-1',
        confirm: 'new-secret-1',
      );
      expect(error, 'Enter your current password.');
    });

    test('new password shorter than the minimum', () async {
      final error = await submitExpectingRejection(
        container: makeContainer(),
        current: 'old-secret-1',
        next: 'short7!',
        confirm: 'short7!',
      );
      expect(
        error,
        'New password must be at least '
        '${ChangePasswordController.minPasswordLength} characters.',
      );
    });

    test('new password equal to the current one', () async {
      final error = await submitExpectingRejection(
        container: makeContainer(),
        current: 'same-secret-1',
        next: 'same-secret-1',
        confirm: 'same-secret-1',
      );
      expect(error, 'New password must be different from your current password.');
    });

    test('confirmation mismatch', () async {
      final error = await submitExpectingRejection(
        container: makeContainer(),
        current: 'old-secret-1',
        next: 'new-secret-1',
        confirm: 'new-secret-2',
      );
      expect(error, 'New passwords do not match.');
    });
  });

  test('an AuthException from the repository surfaces its message', () async {
    final container = makeContainer();
    repo.throwOnChange = AuthException('Current password is incorrect.');

    final ok = await container
        .read(changePasswordControllerProvider.notifier)
        .submit(
          currentPassword: 'wrong-secret',
          newPassword: 'new-secret-1',
          confirmPassword: 'new-secret-1',
        );

    expect(ok, isFalse);
    expect(
      container.read(changePasswordControllerProvider).error,
      'Current password is incorrect.',
    );
  });

  test('an unexpected error falls back to the generic message', () async {
    final container = makeContainer();
    repo.throwOnChange = StateError('boom');

    final ok = await container
        .read(changePasswordControllerProvider.notifier)
        .submit(
          currentPassword: 'old-secret-1',
          newPassword: 'new-secret-1',
          confirmPassword: 'new-secret-1',
        );

    expect(ok, isFalse);
    expect(
      container.read(changePasswordControllerProvider).error,
      'Could not change password. Is the server running?',
    );
  });
}
