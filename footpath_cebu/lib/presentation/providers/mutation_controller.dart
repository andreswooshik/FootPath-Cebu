import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared lifecycle for form writes. Views render state; subclasses supply the
/// operation and the queries to refresh. A closed form cannot publish late state.
abstract class MutationController extends AsyncNotifier<void> {
  bool _running = false;

  @override
  void build() {}

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
