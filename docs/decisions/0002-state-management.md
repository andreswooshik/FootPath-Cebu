# ADR 0002 — State management: migrate the presentation layer to Riverpod

**Status:** Accepted (and implemented) · **Date:** 2026-07-16

> **Amendment (2026-07-16):** the original proposal below recommended freezing
> ChangeNotifier through the defense and adopting Riverpod incrementally
> afterwards. The project owner decided to migrate **now**, before building the
> remaining 50% scope, so every new feature (offline-first attendance, School
> Staff, injuries, feedback) is written once in the final architecture instead
> of being migrated later. The full migration shipped in one PR:
>
> - `flutter_riverpod ^3.3` using the **classic (non-codegen) syntax** — not
>   the `@riverpod` codegen flavor originally recommended. Rationale: zero
>   `build_runner` step and no generated files, which keeps the toolchain
>   simple and every line of state code explainable at the defense; the
>   semantics (`AsyncValue`, `Notifier`, autoDispose, overrides) are identical,
>   and codegen can be layered on later without changing the architecture.
> - The static `ServiceLocator` is replaced by a provider-based composition
>   root (`core/di/providers.dart`): one `Provider` per repository (choosing
>   mock vs live) and per use case. The F1 release guard (`useMockData`) lives
>   there too.
> - Every ViewModel became a provider/controller under
>   `presentation/providers/`; every screen is a `ConsumerWidget` /
>   `ConsumerStatefulWidget`; tests use `ProviderScope` (widgets) and
>   `ProviderContainer` + `overrideWithValue(fake)` (units).
> - The domain layer (entities, repository interfaces, use cases) is
>   completely unchanged — ADR 0001 is unaffected, as predicted below.
> - Two Riverpod 3 behaviors to know: failed providers **auto-retry** with
>   exponential backoff (tests disable this via the container's `retry`
>   parameter), and rebuilds are batched, so several synchronous state changes
>   coalesce into one recompute.
>
> The original analysis is kept below for the record.

## Context

The app uses MVVM with hand-rolled state: ViewModels extend `ChangeNotifier`,
are constructed directly in each screen's `initState` (e.g.
`CoachDashboardViewModel(ServiceLocator.getSquad)`), and dependencies come from a
static service locator (`core/di/service_locator.dart`). Screens rebuild via
`ListenableBuilder`. It is clean, layered (presentation → domain ← data), and
well tested (53 Flutter tests).

Two forces prompt this decision:

1. **Recurring boilerplate.** Every one of the ~8 ViewModels re-implements the
   same async triple by hand: a `_loading` bool, a `_error` string, the loaded
   value, `notifyListeners()` on each transition, and a `try/on
   RepositoryException/catch` block. See `player_dashboard_viewmodel.dart`,
   `coach_dashboard_viewmodel.dart`, `guardian_dashboard_viewmodel.dart`,
   `training_schedule_viewmodel.dart`, `coach_profile_viewmodel.dart`. This cost
   is paid again for every new screen, and the remaining-50% scope adds several
   (School Staff eligibility, injury CRUD, attendance recording).

2. **Where the app is heading.** `docs/REQUIREMENTS.md` commits to
   **offline-first attendance sync** and push-driven updates. That class of
   feature — reactive cache invalidation, connectivity-driven refresh, derived
   state shared across screens — is exactly where a manual `ChangeNotifier` +
   static-locator setup accumulates the most friction.

## Options considered

**A. Stay as-is (ChangeNotifier + static ServiceLocator).**
- *Pros:* zero migration; working, tested, and it is the graded capstone artifact
  demonstrating the team understands the layers by hand. No new concepts.
- *Cons:* the async-state boilerplate grows linearly with screens; the static
  locator is global mutable state (`static late` fields) that complicates scoped
  testing and per-screen lifecycle; no auto-dispose; offline-first will be built
  largely by hand.

**B. Keep ChangeNotifier, swap the locator for the `provider` package.**
- *Pros:* small, low-risk change; fixes DI/lifecycle (scoped, auto-disposed,
  overridable in tests) while keeping the ViewModel mental model.
- *Cons:* doesn't remove the async-state boilerplate and doesn't materially help
  offline-first. It's a stepping stone that would likely be followed by a second
  migration to Riverpod anyway — two migrations instead of one.

**C. Adopt Riverpod (recommended, incrementally).**
- *Pros:* `AsyncValue` + `AsyncNotifier` delete the `_loading/_error/try-catch`
  triple across every screen; `ref.watch` gives automatic derived state (the
  roster's tier-filter + search recompute for free); `autoDispose` + `family`
  handle per-screen and per-argument lifecycle; `ProviderScope` overrides make
  fakes cleaner than swapping a static locator; it is the strongest Flutter
  option for the reactive/offline work coming next.
- *Cons:* real learning curve (providers, `ref`, autoDispose/family, codegen vs
  manual); a half-migrated codebase is worse than either pure state; rewriting
  working, tested screens carries risk with no user-visible payoff.

## Decision

**Do not migrate before the capstone defense. Adopt Riverpod after it, and do it
incrementally — new features first, existing screens opportunistically.**

Concretely:

1. **Freeze the architecture through the defense.** The current pattern is clean,
   tested, and is itself part of what's being graded. Destabilizing it right
   before the defense is bad risk/reward. (This ADR stays *Proposed* until then.)

2. **Make Riverpod the convention for new work in the remaining 50%**, starting
   with **offline-first attendance** — it's greenfield, and it's the feature that
   benefits most from Riverpod's reactive invalidation. Riverpod coexists with
   the existing code: wrap the app in `ProviderScope`; existing `ChangeNotifier`
   screens keep working untouched while new screens use providers.

3. **Migrate existing screens opportunistically**, not in a big-bang rewrite —
   when a screen is already being changed for another reason. Convert its
   ViewModel to an `AsyncNotifier` and its tests to `ProviderContainer` overrides
   in the same PR.

4. **Use code generation (`riverpod_generator` / `@riverpod`)** as the default
   flavor — less boilerplate, better type safety — accepting the `build_runner`
   step. Keep the domain layer (entities, repository interfaces, use cases)
   exactly as-is: providers wrap the *existing* use cases, they don't replace the
   clean-architecture layering. ADR 0001 is unaffected.

5. **Skip option B.** Going straight to Riverpod avoids paying for two migrations.

## Consequences

**Positive**
- New screens shed the async-state boilerplate immediately; derived/shared state
  and offline invalidation become natural rather than hand-built.
- Testing improves: `ProviderContainer` + `overrideWith(fake)` replaces reliance
  on the mutable static locator, giving true per-test isolation.
- One convention going forward instead of each feature inventing its own.

**Trade-offs / risks**
- Temporary duality: two state-management styles coexist during the incremental
  migration. Mitigated by a clear rule (new code = Riverpod) and by keeping the
  domain layer shared, so the split is only in the presentation layer.
- Team ramp-up on Riverpod concepts and codegen. Mitigated by starting on one
  greenfield feature before touching working screens.
- If the app's scope were frozen at today's 8 screens with no offline-first, the
  honest call would flip to **option A (stay)** — the migration only pays off
  because the feature set and the offline requirement are still growing.

## Illustration — Coach dashboard, before and after

*Today (`coach_dashboard_viewmodel.dart` + screen):* a `ChangeNotifier` holding
`_squad`, `_loading`, `_error`, `_query`, `_tierFilter`; a `loadSquad()` with a
`try/on PlayerRepositoryException/catch` that toggles `_loading` and calls
`notifyListeners()` three times; a `players` getter that re-filters manually; and
a screen that news the VM in `initState`, calls `loadSquad()`, disposes it, and
wraps the body in `ListenableBuilder` with manual `isLoading`/`error` branches.

*With Riverpod:*

```dart
@riverpod
Future<List<Player>> squad(SquadRef ref) => ServiceLocator.getSquad();

final tierFilterProvider = StateProvider.autoDispose<AgeTier?>((ref) => null);
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

// Derived state recomputes automatically when the squad, filter, or query change.
@riverpod
AsyncValue<List<Player>> filteredSquad(FilteredSquadRef ref) {
  final tier = ref.watch(tierFilterProvider);
  final q = ref.watch(searchQueryProvider).toLowerCase();
  return ref.watch(squadProvider).whenData((list) => list.where((p) =>
      (tier == null || p.ageTier == tier) &&
      (q.isEmpty || p.name.toLowerCase().contains(q) ||
          p.position.toLowerCase().contains(q))).toList());
}

// Screen: no initState, no dispose, no ListenableBuilder, no manual flags.
class CoachDashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(filteredSquadProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => DashboardErrorState(message: '$e',
          onRetry: () => ref.invalidate(squadProvider)),
      data: (players) => /* grid */,
    );
  }
}
```

The `_loading/_error/notifyListeners` triple and the manual re-filtering are gone;
pull-to-refresh becomes `ref.invalidate(squadProvider)`; and the same shape scales
to offline-first (the squad provider can watch a connectivity/cache provider and
refresh reactively).

## Verification

When adopted, a screen is "migrated" when: its ViewModel is replaced by
provider(s); the screen is a `ConsumerWidget`/`ConsumerStatefulWidget` using
`ref.watch`/`ref.listen`; and its tests use a `ProviderContainer` with
`overrideWith(fake)` instead of constructing the ViewModel with a fake directly.
`flutter test` and `flutter analyze` stay green at every step.
