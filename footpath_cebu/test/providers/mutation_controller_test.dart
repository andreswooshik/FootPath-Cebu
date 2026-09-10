import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

class _Controller extends MutationController {}

final _provider = AsyncNotifierProvider.autoDispose<_Controller, void>(
  _Controller.new,
);

void main() {
  test('duplicate submissions execute the write only once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(_provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(_provider.notifier);
    final pending = Completer<int>();
    var calls = 0;
    var refreshes = 0;
    Future<int> action() {
      calls++;
      return pending.future;
    }

    final first = controller.runMutation(action, onSuccess: (_) => refreshes++);
    expect(await controller.runMutation(action), isNull);
    expect(calls, 1);
    expect(container.read(_provider).isLoading, isTrue);
    pending.complete(42);
    expect(await first, 42);
    expect(refreshes, 1);
    expect(container.read(_provider).hasError, isFalse);
  });

  for (final fail in [false, true]) {
    test('completion after disposal is safe (failure=$fail)', () async {
      final container = ProviderContainer();
      final controller = container.read(_provider.notifier);
      final pending = Completer<int>();
      var refreshed = false;
      final result = controller.runMutation(
        () => pending.future,
        onSuccess: (_) => refreshed = true,
      );
      container.dispose();
      if (fail) {
        pending.completeError(StateError('request failed'));
      } else {
        pending.complete(1);
      }
      expect(await result, isNull);
      expect(refreshed, isFalse);
    });
  }

  test('failed writes expose an error and allow an explicit retry', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(_provider.notifier);
    expect(
      await controller.runMutation<int>(() async => throw StateError('failed')),
      isNull,
    );
    expect(container.read(_provider).hasError, isTrue);
    expect(await controller.runMutation(() async => 1), 1);
    expect(container.read(_provider).hasError, isFalse);
  });
}
