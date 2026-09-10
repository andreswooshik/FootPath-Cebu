part of 'log_attendance_screen.dart';

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
        AttendanceSyncStatus(sessionId: session.id),
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
    required this.hasSavedAttendance,
    required this.onFinalize,
  });

  final int markedCount;
  final int presentCount;
  final int unmarkedCount;
  final bool isSaving;

  /// Whether attendance may be logged now — false unless it's the session day.
  final bool canLog;
  final bool hasSavedAttendance;
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
                  : Icon(
                      !canLog
                          ? Icons.lock_clock
                          : hasSavedAttendance
                          ? Icons.save_as_outlined
                          : Icons.how_to_reg,
                    ),
              label: Text(
                isSaving
                    ? 'Saving…'
                    : !canLog
                    ? 'Available on the session day'
                    : hasSavedAttendance
                    ? 'Update Changes'
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
