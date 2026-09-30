import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared lifecycle for form writes. Views render state; subclasses supply the
/// operation and the queries to refresh. A closed form cannot publish late state.
abstract class MutationController extends AsyncNotifier<void> {
  bool _running = false;

  /// Initializes the shared mutation controller with no pending write.
  @override
  void build() {}

  /// Runs one write at a time, publishes loading/errors, and calls onSuccess
  /// only while mounted.
  Future<T?> runMutation<T>(
    Future<T> Function() action, {
    void Function(T result)? onSuccess,
  }) async {
    if (!ref.mounted || _running) return null;
    _running = true;
    state = const AsyncLoading();
    try {
      final result = await action();
      if (!ref.mounted) return null;
      state = const AsyncData(null);
      onSuccess?.call(result);
      return result;
    } catch (error, stackTrace) {
      if (ref.mounted) state = AsyncError(error, stackTrace);
      return null;
    } finally {
      _running = false;
    }
  }
}
