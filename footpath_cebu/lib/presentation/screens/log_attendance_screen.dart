import 'package:flutter/material.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_sync_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/attendance_log_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

part 'log_attendance_components.dart';

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
  bool _hasSavedAttendance = false;

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
      final delivery = ref
          .read(attendanceLogControllerProvider.notifier)
          .lastDeliveryStatus;
      final message = switch (delivery) {
        AttendanceDeliveryStatus.savedOnServer =>
          'Saved on server — $presentCount present.',
        AttendanceDeliveryStatus.waitingToSync =>
          'Saved on this device — waiting to sync. View Attendance sync for progress.',
        AttendanceDeliveryStatus.needsCorrection =>
          'Saved on this device — needs correction. Open Attendance sync to review.',
        AttendanceDeliveryStatus.unknown =>
          'Attendance saved. Sync status is unavailable; check Attendance sync.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
    _hasSavedAttendance = existing.isNotEmpty;
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
        appBar: AppBar(
          title: const Text('Attendance'),
          actions: const [AttendanceSyncButton()],
        ),
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
                hasSavedAttendance: _hasSavedAttendance,
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
