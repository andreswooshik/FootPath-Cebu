import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';

/// A single training session on the coach's schedule: a coloured age-tier
/// header with the date, and a body with the title, time, location, attendees
/// and a Log Attendance action. Colours are drawn from the app's [ColorScheme]
/// so the card stays on-theme.
class TrainingSessionCard extends StatelessWidget {
  const TrainingSessionCard({
    super.key,
    required this.session,
    this.onLogAttendance,
    this.onTap,
  });

  final TrainingSession session;
  final VoidCallback? onLogAttendance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tier = _tierColors(session, cs);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured tier header with the date.
            Container(
              color: tier.bg,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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

                  const SizedBox(height: 12),
                  Text(
                    _formatDate(session.date),
                    style: TextStyle(
                      color: tier.fg,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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
                  Text(
                    session.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.access_time,
                    text: '${session.startTime} - ${session.endTime}',
                  ),
                  const SizedBox(height: 6),
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    text: session.location,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _Attendees(
                        count: session.attendeeCount,
                        color: cs.primary,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: onLogAttendance,
                        style: TextButton.styleFrom(
                          foregroundColor: cs.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Text('Log Attendance'),
                        label: const Icon(Icons.chevron_right, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
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

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';
