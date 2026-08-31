import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/attendance_log_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

/// Coach Portal — Attendance & Evaluation for one training session.
///
/// A thin View over the attendance providers. Following the same convention as
/// the Schedule Session and Edit Performance forms, the transient marks live
/// here in the State and are handed to [AttendanceLogController.save] as a
/// finished list.
///
/// This is a task screen reached by tapping a session, not a tab, so it has no
/// [CoachBottomNav] — the bottom slot carries the finalise action, and there's
/// nowhere to wander off to mid-roll-call.
///
/// Scope note: the per-session evaluation here is attendance + effort + a
/// remark. The six long-lived attribute ratings live in
/// [EditPerformanceDataScreen], reachable per player — a player doesn't lose 3
/// Pace because they had an off day.
class LogAttendanceScreen extends ConsumerStatefulWidget {
  const LogAttendanceScreen({
    super.key,
    required this.session,
    required this.profile,
    this.initialAttendance,
  });

  final TrainingSession session;

  /// The signed-in coach, forwarded to the per-player assessment form.
  final UserProfile profile;

  /// Saved records preloaded by the schedule screen. Passing the completed
  /// snapshot prevents the roster from briefly painting every player as
  /// unmarked while the same request finishes on this route.
  final List<Attendance>? initialAttendance;

  @override
  ConsumerState<LogAttendanceScreen> createState() =>
      _LogAttendanceScreenState();
}

class _LogAttendanceScreenState extends ConsumerState<LogAttendanceScreen> {
  /// The coach's marks so far, by player id. Transient form state — unmarked
  /// players are simply absent from the map (null status is a real, distinct
  /// state from "absent").
  final Map<String, Attendance> _marks = {};

  /// Existing saved marks are copied into [_marks] exactly once, the first time
  /// the roster and saved attendance are both available.
  bool _seeded = false;

  bool get _dirty => _dirtySince;
  bool _dirtySince = false;

  // -- derived counts, computed against the eligible roster ------------------

  int _presentCount() =>
      _marks.values.where((a) => a.status == AttendanceStatus.present).length;

  // -- mark mutations --------------------------------------------------------

  void _mark(String playerId, AttendanceStatus? status) {
    setState(() {
      _dirtySince = true;
      if (status == null) {
        _marks.remove(playerId);
        return;
      }
      final existing = _marks[playerId];
      _marks[playerId] = existing == null
          ? Attendance(
              playerId: playerId,
              status: status,
              updatedAt: DateTime.now(),
              sessionId: widget.session.id,
              sessionName: widget.session.title,
              effort: status == AttendanceStatus.present
                  ? kDefaultEffort
                  : null,
            )
          : existing.copyWith(
              status: status,
              updatedAt: DateTime.now(),
              effort: status == AttendanceStatus.present
                  ? existing.effort ?? kDefaultEffort
                  : null,
              clearParticipationValues: status != AttendanceStatus.present,
            );
    });
  }

  void _markAllPresent(List<Player> roster) {
    setState(() {
      _dirtySince = true;
      for (final player in roster) {
        _marks.putIfAbsent(
          player.id,
          () => Attendance(
            playerId: player.id,
            status: AttendanceStatus.present,
            updatedAt: DateTime.now(),
            sessionId: widget.session.id,
            sessionName: widget.session.title,
            effort: kDefaultEffort,
          ),
        );
      }
    });
  }

  /// Effort/note updates don't setState — the slider and field own their own
  /// value while editing, and rebuilding the list on every keystroke or drag
  /// frame would fight the cursor and waste work.
  void _setEffort(String playerId, int effort) {
    final draft = _marks[playerId];
    if (draft == null) return;
    _marks[playerId] = draft.copyWith(effort: effort);
    _dirtySince = true;
  }

  void _setNote(String playerId, String note) {
    final draft = _marks[playerId];
    if (draft == null) return;
    _marks[playerId] = draft.copyWith(note: note);
    _dirtySince = true;
  }

  void _setPerformanceScore(String playerId, double? score) {
    final draft = _marks[playerId];
    if (draft == null) return;
    _marks[playerId] = draft.copyWith(
      performanceScore: score,
      clearPerformanceScore: score == null,
    );
    _dirtySince = true;
  }

  // -- navigation / finalise -------------------------------------------------

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard attendance?'),
        content: const Text(
          "You've marked players but haven't saved yet. Leaving now loses "
          'those marks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _finalize(List<Player> roster) async {
    // Attendance is a record of who showed up — the coach can log it on the
    // session day and up to two days after, never before. The button is
    // already disabled outside that window; this guards the path anyway (and
    // the server enforces it too).
    if (!widget.session.isAttendanceOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Attendance can only be logged on the session day or up to '
            '2 days after.',
          ),
        ),
      );
      return;
    }

    final unmarked = roster.length - _marks.length;
    if (unmarked > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some players are unmarked'),
          content: Text(
            '$unmarked of ${roster.length} players have no attendance yet. '
            "They won't be recorded at all — neither present nor absent.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Go back'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Effort and notes are dropped for anyone not present: they describe how
    // someone trained, and a player who wasn't there didn't. Rebuilt rather
    // than copyWith'd — copyWith reads `effort ?? this.effort`, so it can't
    // clear a field.
    final records = _marks.values
        .map(
          (a) => a.status == AttendanceStatus.present
              ? a
              : Attendance(
                  playerId: a.playerId,
                  status: a.status,
                  updatedAt: a.updatedAt,
                  sessionId: a.sessionId,
                  sessionName: a.sessionName,
                ),
        )
        .toList(growable: false);

    final presentCount = _presentCount();
    final ok = await ref
        .read(attendanceLogControllerProvider.notifier)
        .save(widget.session.id, records);
    if (!mounted) return;
    if (ok) {
      _dirtySince = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attendance saved — $presentCount present.')),
      );
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(attendanceLogControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not save attendance.'),
          ),
        ),
      );
    }
  }

  void _openAssessment(Player player) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EditPerformanceDataScreen(player: player, profile: widget.profile),
      ),
    );
  }

  /// Copies saved marks for roster players into [_marks], once.
  void _seedOnce(List<Player> roster, List<Attendance> existing) {
    if (_seeded) return;
    _seeded = true;
    for (final record in existing) {
      if (roster.any((p) => p.id == record.playerId)) {
        _marks[record.playerId] = record;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final squadAsync = ref.watch(squadProvider);
    final existingAsync = widget.initialAttendance == null
        ? ref.watch(sessionAttendanceProvider(widget.session.id))
        : AsyncData(widget.initialAttendance!);
    final isSaving = ref.watch(attendanceLogControllerProvider).isLoading;

    // Both sources feed the roster; combine them so we show one loading state.
    final rosterAsync = squadAsync.whenData(
      (squad) => squad
          .where((p) => widget.session.includesTier(p.ageTier))
          .toList(growable: false),
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Attendance')),
        body: rosterAsync.when(
          loading: () => const DashboardLoadingState(),
          error: (e, _) => DashboardErrorState(
            message: friendlyErrorMessage(
              e,
              'Something went wrong loading the roster.',
            ),
            onRetry: () => ref.invalidate(squadProvider),
          ),
          data: (roster) => existingAsync.when(
            // Never display a blank roll call before saved marks arrive. That
            // looks like attendance was not logged and exposes an incorrect
            // draft for a few seconds.
            loading: () => const DashboardLoadingState(),
            error: (e, _) => DashboardErrorState(
              message: friendlyErrorMessage(
                e,
                'Could not load the saved attendance for this session.',
              ),
              onRetry: () =>
                  ref.invalidate(sessionAttendanceProvider(widget.session.id)),
            ),
            data: (existing) {
              _seedOnce(roster, existing);
              return _Body(
                session: widget.session,
                roster: roster,
                state: this,
              );
            },
          ),
        ),
        bottomNavigationBar: rosterAsync.maybeWhen(
          data: (roster) => existingAsync.maybeWhen(
            data: (existing) {
              _seedOnce(roster, existing);
              return _FinalizeBar(
                markedCount: _marks.length,
                presentCount: _presentCount(),
                unmarkedCount: roster.length - _marks.length,
                isSaving: isSaving,
                canLog: widget.session.isAttendanceOpen,
                onFinalize: () => _finalize(roster),
              );
            },
            orElse: () => null,
          ),
          orElse: () => null,
        ),
      ),
    );
  }
}

/// The scrolling content: session header + player list. Reads and mutates the
/// screen State directly, so marks and derived counts stay in one place.
class _Body extends StatelessWidget {
  const _Body({
    required this.session,
    required this.roster,
    required this.state,
  });

  final TrainingSession session;
  final List<Player> roster;
  final _LogAttendanceScreenState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionHeader(
          session: session,
          totalPlayers: roster.length,
          markedCount: state._marks.length,
          onMarkAllPresent: () => state._markAllPresent(roster),
        ),
        Expanded(
          child: roster.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No players are registered in ${session.tiersLabel} '
                      'yet, so there is nobody to mark for this session.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: roster.length,
                  itemBuilder: (context, i) {
                    final player = roster[i];
                    return _PlayerAttendanceCard(
                      key: ValueKey(player.id),
                      player: player,
                      status: state._marks[player.id]?.status,
                      effort: state._marks[player.id]?.effort ?? kDefaultEffort,
                      performanceScore:
                          state._marks[player.id]?.performanceScore,
                      note: state._marks[player.id]?.note ?? '',
                      onMark: (s) => state._mark(player.id, s),
                      onEffort: (v) => state._setEffort(player.id, v),
                      onPerformanceScore: (v) =>
                          state._setPerformanceScore(player.id, v),
                      onNote: (v) => state._setNote(player.id, v),
                      onOpenAssessment: () => state._openAssessment(player),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Session details plus roll-call progress. The progress line answers the
/// coach's real question — "did I miss anyone?" — without scrolling.
class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.session,
    required this.totalPlayers,
    required this.markedCount,
    required this.onMarkAllPresent,
  });

  final TrainingSession session;
  final int totalPlayers;
  final int markedCount;
  final VoidCallback onMarkAllPresent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unmarked = totalPlayers - markedCount;
    final progress = totalPlayers == 0 ? 0.0 : markedCount / totalPlayers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, size: 13, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'SESSION DETAILS',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(session.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            '${_formatDate(session.date)} · '
            '${session.startTime} - ${session.endTime}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.location_on_outlined,
                label: session.location,
              ),
              _MetaChip(icon: Icons.groups_outlined, label: session.tiersLabel),
              _MetaChip(
                icon: Icons.person_outline,
                label: '$totalPlayers players',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$markedCount of $totalPlayers marked',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (unmarked > 0)
                TextButton.icon(
                  onPressed: onMarkAllPresent,
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Mark all present'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// One outlined pill of session metadata.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One player's row: identity, a three-way attendance control, and — only once
/// they're marked present — the session evaluation.
class _PlayerAttendanceCard extends StatelessWidget {
  const _PlayerAttendanceCard({
    super.key,
    required this.player,
    required this.status,
    required this.effort,
    required this.performanceScore,
    required this.note,
    required this.onMark,
    required this.onEffort,
    required this.onPerformanceScore,
    required this.onNote,
    required this.onOpenAssessment,
  });

  final Player player;
  final AttendanceStatus? status;
  final int effort;
  final double? performanceScore;
  final String note;
  final ValueChanged<AttendanceStatus?> onMark;
  final ValueChanged<int> onEffort;
  final ValueChanged<double?> onPerformanceScore;
  final ValueChanged<String> onNote;
  final VoidCallback onOpenAssessment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPresent = status == AttendanceStatus.present;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _PlayerAvatar(player: player),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${player.position?.code ?? 'No position'} · ${player.ageTier.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (status == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Unmarked',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _AttendanceSelector(status: status, onChanged: onMark),
            // Collapse rather than disable: an evaluation for someone who
            // wasn't there is noise, and the spec is "expand when present".
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: isPresent
                  ? _SessionEvaluation(
                      // Re-key per status so the slider/field re-seed from the
                      // map when a mark toggles back to present.
                      key: ValueKey('${player.id}-present'),
                      effort: effort,
                      performanceScore: performanceScore,
                      note: note,
                      onEffort: onEffort,
                      onPerformanceScore: onPerformanceScore,
                      onNote: onNote,
                      onOpenAssessment: onOpenAssessment,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player's photo, or their initial when no photo is set.
class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final url = player.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: 22, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: 22,
      child: Text(
        player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Present / Absent / Excused, one tap each.
///
/// A segmented button suits three short, fixed labels — unlike the age-tier
/// filter, where four long labels couldn't fit a phone's width. Colours follow
/// [AttendanceStatusChip] so the coach and guardian views agree on what green
/// and red mean.
class _AttendanceSelector extends StatelessWidget {
  const _AttendanceSelector({required this.status, required this.onChanged});

  final AttendanceStatus? status;
  final ValueChanged<AttendanceStatus?> onChanged;

  static const _colors = {
    AttendanceStatus.present: Colors.green,
    AttendanceStatus.absent: Colors.red,
    AttendanceStatus.excused: Colors.blueGrey,
  };

  static const _icons = {
    AttendanceStatus.present: Icons.check_circle_outline,
    AttendanceStatus.absent: Icons.cancel_outlined,
    AttendanceStatus.excused: Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final selected = _colors[status] ?? Theme.of(context).colorScheme.primary;
    return SegmentedButton<AttendanceStatus>(
      segments: [
        for (final s in AttendanceStatus.values)
          ButtonSegment(
            value: s,
            label: Text(s.label),
            icon: Icon(_icons[s], size: 16),
          ),
      ],
      selected: status == null ? const {} : {status!},
      // Nothing selected is a real state, so the control must tolerate it.
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.isEmpty ? null : set.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: selected.withValues(alpha: 0.16),
        selectedForegroundColor: selected,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The session-scoped evaluation: how this player trained today.
class _SessionEvaluation extends StatelessWidget {
  const _SessionEvaluation({
    super.key,
    required this.effort,
    required this.performanceScore,
    required this.note,
    required this.onEffort,
    required this.onPerformanceScore,
    required this.onNote,
    required this.onOpenAssessment,
  });

  final int effort;
  final double? performanceScore;
  final String note;
  final ValueChanged<int> onEffort;
  final ValueChanged<double?> onPerformanceScore;
  final ValueChanged<String> onNote;
  final VoidCallback onOpenAssessment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 10),
        _EffortSlider(initialValue: effort, onChanged: onEffort),
        const SizedBox(height: 8),
        _PerformanceScoreInput(
          initialValue: performanceScore,
          onChanged: onPerformanceScore,
        ),
        const SizedBox(height: 8),
        _NoteField(initialValue: note, onChanged: onNote),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onOpenAssessment,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Full assessment'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }
}

/// Effort/intensity, 0-100. Owns its displayed value while dragging and reports
/// out on change, so a drag doesn't rebuild the whole roster every frame.
class _EffortSlider extends StatefulWidget {
  const _EffortSlider({required this.initialValue, required this.onChanged});

  final int initialValue;
  final ValueChanged<int> onChanged;

  @override
  State<_EffortSlider> createState() => _EffortSliderState();
}

class _EffortSliderState extends State<_EffortSlider> {
  late int _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Effort / Intensity',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '$_value%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: _value.toDouble(),
            max: 100,
            divisions: 20,
            label: '$_value%',
            onChanged: (v) {
              setState(() => _value = v.round());
              widget.onChanged(_value);
            },
          ),
        ),
      ],
    );
  }
}

/// Optional 0.0-10.0 execution-quality score. A switch makes the missing state
/// explicit instead of silently treating "not rated" as zero.
class _PerformanceScoreInput extends StatefulWidget {
  const _PerformanceScoreInput({
    required this.initialValue,
    required this.onChanged,
  });

  final double? initialValue;
  final ValueChanged<double?> onChanged;

  @override
  State<_PerformanceScoreInput> createState() => _PerformanceScoreInputState();
}

class _PerformanceScoreInputState extends State<_PerformanceScoreInput> {
  late bool _enabled = widget.initialValue != null;
  late double _value = widget.initialValue ?? 7.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Training performance score'),
          subtitle: const Text(
            'Optional execution quality, separate from effort',
          ),
          value: _enabled,
          onChanged: (enabled) {
            setState(() => _enabled = enabled);
            widget.onChanged(enabled ? _value : null);
          },
        ),
        if (_enabled)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _value,
                  min: 0,
                  max: 10,
                  divisions: 100,
                  label: _value.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() => _value = value);
                    widget.onChanged(double.parse(value.toStringAsFixed(1)));
                  },
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  _value.toStringAsFixed(1),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The coach's remark for this session. Owns its controller so the text
/// survives the list rebuilding around it.
class _NoteField extends StatefulWidget {
  const _NoteField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: 2,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Remarks for this session…',
        hintStyle: const TextStyle(fontSize: 13),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// The persistent finalise action.
class _FinalizeBar extends StatelessWidget {
  const _FinalizeBar({
    required this.markedCount,
    required this.presentCount,
    required this.unmarkedCount,
    required this.isSaving,
    required this.canLog,
    required this.onFinalize,
  });

  final int markedCount;
  final int presentCount;
  final int unmarkedCount;
  final bool isSaving;

  /// Whether attendance may be logged now — false unless it's the session day.
  final bool canLog;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!canLog)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_clock,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Attendance can only be logged on the session day or '
                        'up to 2 days after.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (unmarkedCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '$unmarkedCount still unmarked',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            FilledButton.icon(
              onPressed: !canLog || isSaving || markedCount == 0
                  ? null
                  : onFinalize,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(canLog ? Icons.how_to_reg : Icons.lock_clock),
              label: Text(
                isSaving
                    ? 'Saving…'
                    : !canLog
                    ? 'Available on the session day'
                    : 'Complete Training Session'
                          '${markedCount > 0 ? ' ($presentCount present)' : ''}',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
