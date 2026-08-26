import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/screens/player_privacy_pin_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

/// Responsive player picker for guardian PIN management.
class GuardianPrivacyPinSelectionScreen extends ConsumerWidget {
  const GuardianPrivacyPinSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(linkedPlayersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Player privacy PINs')),
      body: players.when(
        loading: () => const DashboardLoadingState(compact: true),
        error: (error, _) => _LoadError(
          message: friendlyErrorMessage(error, 'Could not load players.'),
          onRetry: () => ref.invalidate(linkedPlayersProvider),
        ),
        data: (children) => children.isEmpty
            ? const _EmptyPlayersState()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isTablet = constraints.maxWidth >= 700;
                  return SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: CustomScrollView(
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                isTablet ? 32 : 20,
                                isTablet ? 32 : 24,
                                isTablet ? 32 : 20,
                                22,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: _SelectionHeader(
                                  playerCount: children.length,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                isTablet ? 32 : 16,
                                0,
                                isTablet ? 32 : 16,
                                28,
                              ),
                              sliver: SliverGrid.builder(
                                itemCount: children.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: isTablet ? 2 : 1,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                      mainAxisExtent: 132,
                                    ),
                                itemBuilder: (context, index) {
                                  final player = children[index];
                                  final status = ref.watch(
                                    playerPrivacyPinStatusProvider(player.id),
                                  );
                                  return _PlayerPinCard(
                                    name: player.name,
                                    status: status,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PlayerPrivacyPinScreen(
                                          player: player,
                                          isGuardian: true,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ).animateScreenEntrance();
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({required this.playerCount});

  final int playerCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(
            Icons.family_restroom_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a player', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Create, review, or reset the privacy PIN for a linked player.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$playerCount linked ${playerCount == 1 ? 'player' : 'players'}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerPinCard extends StatelessWidget {
  const _PlayerPinCard({
    required this.name,
    required this.status,
    required this.onTap,
  });

  final String name;
  final AsyncValue<PlayerPrivacyPinStatus> status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PinStatus(status: status),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinStatus extends StatelessWidget {
  const _PinStatus({required this.status});

  final AsyncValue<PlayerPrivacyPinStatus> status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return status.when(
      loading: () => Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 7),
          const Text('Checking PIN status…'),
        ],
      ),
      error: (_, _) => _StatusPill(
        label: 'Status unavailable',
        icon: Icons.info_outline,
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
      ),
      data: (value) => _StatusPill(
        label: value.hasPin ? 'PIN active' : 'Set up PIN',
        icon: value.hasPin
            ? Icons.check_circle_outline
            : Icons.add_circle_outline,
        background: value.hasPin
            ? colors.primaryContainer
            : colors.secondaryContainer,
        foreground: value.hasPin
            ? colors.onPrimaryContainer
            : colors.onSecondaryContainer,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlayersState extends StatelessWidget {
  const _EmptyPlayersState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No linked players yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'A linked player will appear here when their profile is available.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
