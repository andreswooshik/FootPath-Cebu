import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// Primary player identity card using the five independent development domains.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.player, this.onTap});

  final Player player;
  final VoidCallback? onTap;

  static const _domainLabels = {
    'technical': 'Technical',
    'tactical': 'Tactical',
    'physical': 'Physical',
    'mental': 'Mental',
    'socialValues': 'Values',
  };

  @override
  Widget build(BuildContext context) {
    final assessment = player.developmentAssessment;
    final position = player.position?.labelWithCode ?? 'Position not assigned';
    final positionCode = player.position?.code ?? 'Position not assigned';
    return MotionPress(
      child: Semantics(
        container: true,
        button: onTap != null,
        label: [
          player.name,
          position,
          player.ageTier.label,
          assessment == null
              ? 'no development assessment yet'
              : 'five development domains assessed',
        ].join(', '),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Photo(photoUrl: player.photoUrl, name: player.name),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(positionCode),
                            Text(
                              player.ageTier.label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  if (assessment == null)
                    const Row(
                      children: [
                        Icon(Icons.hourglass_empty_outlined),
                        SizedBox(width: 10),
                        Expanded(child: Text('No development assessment yet')),
                      ],
                    )
                  else ...[
                    Text(
                      'Development domains',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in _domainLabels.entries)
                            SizedBox(
                              width: (constraints.maxWidth - 8) / 2,
                              child: _DomainBadge(
                                label: entry.value,
                                score: assessment.domainScores[entry.key],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (player.academicEligibilityApplicable) ...[
                    const SizedBox(height: 12),
                    Chip(
                      avatar: Icon(
                        _eligibilityIcon(player.eligibility),
                        size: 16,
                      ),
                      label: Text(player.eligibility.label),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 30,
    backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
    child: photoUrl == null ? Text(name.isEmpty ? '?' : name[0]) : null,
  );
}

class _DomainBadge extends StatelessWidget {
  const _DomainBadge({required this.label, required this.score});

  final String label;
  final double? score;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          score?.toStringAsFixed(1) ?? '—',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

IconData _eligibilityIcon(EligibilityStatus status) => switch (status) {
  EligibilityStatus.eligible => Icons.check_circle_outline,
  EligibilityStatus.notEligible => Icons.cancel_outlined,
  EligibilityStatus.pending => Icons.schedule_outlined,
  EligibilityStatus.academicWarning => Icons.warning_amber_outlined,
};
