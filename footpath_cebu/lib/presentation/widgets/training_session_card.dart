import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/widgets/tear_away_date.dart';

/// A single training session, shared by the Coach's and Player/Guardian's
/// schedules: a coloured age-tier header with the date, and a body with the
/// title, time, and location. The row below that is role-specific — the
/// Coach sees attendees + a Log Attendance action ([onLogAttendance]); the
/// Player sees a session-confirmation control instead ([trailing]). Colours
/// are drawn from the app's [ColorScheme] so the card stays on-theme.
class TrainingSessionCard extends StatelessWidget {
  const TrainingSessionCard({
    super.key,
    required this.session,
    this.onLogAttendance,
    this.onTap,
    this.trailing,
    this.onEdit,
    this.onCancelSession,
    this.showPlayerDetails = false,
  });

  final TrainingSession session;
  final VoidCallback? onLogAttendance;
  final VoidCallback? onTap;

  /// Replaces the attendees/Log Attendance row when set — used by the
  /// Player's schedule for a session-confirmation control instead of the
  /// Coach's roll-call action.
  final Widget? trailing;

  /// Coach-only management actions; when either is set, a ⋮ menu appears
  /// beside the title.
  final VoidCallback? onEdit;
  final VoidCallback? onCancelSession;

  /// Uses explicit labels for the details a player or guardian needs to scan:
  /// training focus, schedule, venue, and age category.
  final bool showPlayerDetails;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tier = _tierColors(session, cs);

    return MotionPress(
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Coloured tier header with a tear-away calendar date.
              Container(
                color: tier.bg,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TearAwayDate(date: session.date, headerColor: cs.tertiary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _TierPill(
                                    label: _tierLabel(session),
                                    fg: tier.fg,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _focusIcon(session.focus),
                                size: 30,
                                color: tier.fg.withValues(alpha: 0.8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _weekdayLong(session.date),
                            style: TextStyle(
                              color: tier.fg,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Details.
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (onEdit != null || onCancelSession != null)
                          PopupMenuButton<String>(
                            tooltip: 'Manage session',
                            padding: EdgeInsets.zero,
                            onSelected: (choice) => choice == 'edit'
                                ? onEdit?.call()
                                : onCancelSession?.call(),
                            itemBuilder: (_) => [
                              if (onEdit != null)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit session'),
                                ),
                              if (onCancelSession != null)
                                const PopupMenuItem(
                                  value: 'cancel',
                                  child: Text('Cancel session'),
                                ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (showPlayerDetails) ...[
                      _DetailRow(
                        icon: Icons.sports_soccer_outlined,
                        label: 'Training focus',
                        text: session.focus.label,
                      ),
                      const SizedBox(height: 6),
                    ],
                    _DetailRow(
                      icon: Icons.access_time,
                      label: showPlayerDetails ? 'Schedule' : null,
                      text: '${session.startTime} - ${session.endTime}',
                    ),
                    const SizedBox(height: 6),
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: showPlayerDetails ? 'Where' : null,
                      text: session.location,
                    ),
                    if (showPlayerDetails) ...[
                      const SizedBox(height: 6),
                      _DetailRow(
                        icon: Icons.groups_outlined,
                        label: 'Age category',
                        text: session.tiersLabel,
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (trailing != null)
                      Align(alignment: Alignment.centerRight, child: trailing)
                    else if (onLogAttendance != null)
                      Row(
                        children: [
                          _Attendees(
                            count: session.attendeeCount,
                            color: cs.primary,
                          ),
                          const Spacer(),
                          // Attendance is logged from the session day through two
                          // days after — the action stays visible but disabled
                          // outside that window, so the coach sees it exists and
                          // why it's not available (a future session) or closed.
                          TextButton.icon(
                            onPressed: session.isAttendanceOpen
                                ? onLogAttendance
                                : null,
                            style: TextButton.styleFrom(
                              foregroundColor: cs.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            icon: Text(
                              session.isAttendanceOpen
                                  ? 'Log Attendance'
                                  : 'Log on the day',
                            ),
                            label: Icon(
                              session.isAttendanceOpen
                                  ? Icons.chevron_right
                                  : Icons.lock_clock,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Translucent pill naming the age tier, on the coloured header.
class _TierPill extends StatelessWidget {
  const _TierPill({required this.label, required this.fg});

  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text, this.label});

  final IconData icon;
  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (label != null)
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                TextSpan(text: text),
              ],
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// A small stack of avatar circles with a "+N" total attendee count.
class _Attendees extends StatelessWidget {
  const _Attendees({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const faces = 3;
    return Row(
      children: [
        SizedBox(
          width: 24.0 + (faces - 1) * 16,
          height: 28,
          child: Stack(
            children: [
              for (var i = 0; i < faces; i++)
                Positioned(
                  left: i * 16.0,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Color.lerp(
                        color,
                        Colors.black,
                        i * 0.15,
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count+',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// The header colour. A session for a single tier is colour-coded to that
/// tier so the schedule is scannable; multi-tier sessions get one distinct
/// colour of their own rather than arbitrarily borrowing a member tier's.
({Color bg, Color fg}) _tierColors(TrainingSession session, ColorScheme cs) {
  if (session.ageTiers.length != 1) {
    return (bg: cs.tertiary, fg: cs.onTertiary);
  }
  switch (session.ageTiers.first) {
    case AgeTier.foundation:
      return (bg: cs.secondaryContainer, fg: cs.onSecondaryContainer);
    case AgeTier.development:
      return (bg: cs.primaryContainer, fg: cs.onPrimaryContainer);
    case AgeTier.pathway:
      return (bg: cs.primary, fg: cs.onPrimary);
  }
}

/// Names the session's tiers in one pill: "All Tiers" when it targets
/// everything, otherwise the tier names joined — "Foundation · Development".
String _tierLabel(TrainingSession session) {
  if (session.ageTiers.isEmpty) return 'No tiers';
  if (session.isAllTiers) return 'All Tiers';
  return session.orderedTiers.map((t) => t.label).join(' · ');
}

IconData _focusIcon(SessionFocus focus) {
  switch (focus) {
    case SessionFocus.technical:
      return Icons.sports_soccer;
    case SessionFocus.physical:
      return Icons.fitness_center;
    case SessionFocus.mental:
      return Icons.psychology_outlined;
  }
}

const _weekdaysLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekdayLong(DateTime d) => _weekdaysLong[d.weekday - 1];
