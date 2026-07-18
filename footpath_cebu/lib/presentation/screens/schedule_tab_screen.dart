import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/session_confirmation_button.dart';
import 'package:footpath_cebu/presentation/widgets/training_session_card.dart';

/// Schedule tab — upcoming/past training sessions. Shared by the Player and
/// Guardian portals (unlike the Coach's Training Schedule screen, there's no
/// "Schedule New Session" action here). Upcoming sessions carry a
/// confirmation control so [player] can RSVP; past sessions don't.
class ScheduleTabScreen extends ConsumerStatefulWidget {
  const ScheduleTabScreen({super.key, required this.player});

  final Player player;

  @override
  ConsumerState<ScheduleTabScreen> createState() => _ScheduleTabScreenState();
}

class _ScheduleTabScreenState extends ConsumerState<ScheduleTabScreen> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(
      _showPast ? pastSessionsProvider : upcomingSessionsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, size: 20),
            SizedBox(width: 8),
            Text('FootPath Cebu'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: _ScheduleTabs(
              showPast: _showPast,
              onChanged: (past) => setState(() => _showPast = past),
            ),
          ),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => DashboardErrorState(
                message: friendlyErrorMessage(
                  e,
                  'Something went wrong loading the schedule.',
                ),
                onRetry: () => ref.invalidate(trainingSessionsProvider),
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Text(
                      _showPast
                          ? 'No past sessions yet.'
                          : 'No upcoming sessions.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(trainingSessionsProvider.future),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) => TrainingSessionCard(
                      session: sessions[i],
                      trailing: _showPast
                          ? null
                          : SessionConfirmationButton(
                              sessionId: sessions[i].id,
                              playerId: widget.player.id,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The Upcoming / Past Sessions segmented toggle.
class _ScheduleTabs extends StatelessWidget {
  const _ScheduleTabs({required this.showPast, required this.onChanged});

  final bool showPast;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TabButton(
            label: 'Upcoming',
            selected: !showPast,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TabButton(
            label: 'Past Sessions',
            selected: showPast,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
