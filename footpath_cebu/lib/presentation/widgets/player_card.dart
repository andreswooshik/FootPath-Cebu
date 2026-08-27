import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// A FUT-style squad card. The ornate frame is an SVG asset
/// (`assets/cards/card_frame.svg`); the live values — overall, position,
/// photo, name, the six stats and the applicable eligibility badge — are overlaid on
/// top, positioned in the frame's 600x850 coordinate space so they line up
/// at any card size. Change a rating in the coach's assessment and the card
/// updates automatically.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.player, this.onTap});

  final Player player;
  final VoidCallback? onTap;

  // The frame's design canvas. All overlay coordinates below are in these
  // units and scaled to the real card width at build time.
  static const double _canvasW = 600;
  static const double _canvasH = 850;

  static const Color _gold = Color(0xFFE7C86A);
  static const Color _bannerInk = Color(0xFF072A1F);

  @override
  Widget build(BuildContext context) {
    final r = player.ratings;
    final position = player.position?.labelWithCode ?? 'Position not assigned';
    final semanticsParts = [
      player.name,
      position,
      player.ageTier.label,
      'overall rating ${player.overall}',
      if (player.academicEligibilityApplicable) player.eligibility.label,
    ];
    return MotionPress(
      child: Semantics(
        container: true,
        button: onTap != null,
        label: semanticsParts.join(', '),
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: _canvasW / _canvasH,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Pixels per design unit — everything scales from this.
                  final s = constraints.maxWidth / _canvasW;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: SvgPicture.asset(
                          'assets/cards/card_frame.svg',
                          fit: BoxFit.fill,
                        ),
                      ),

                      // Player photo (behind the rating corner).
                      _place(
                        s,
                        x: 170,
                        y: 140,
                        w: 260,
                        h: 260,
                        child: _Photo(photoUrl: player.photoUrl),
                      ),

                      // Overall rating + position, top-left.
                      _place(
                        s,
                        x: 46,
                        y: 148,
                        w: 148,
                        h: 104,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${player.overall}',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 58 * s,
                                height: 1,
                              ),
                            ),
                            Text(
                              player.position?.code ?? '--',
                              style: TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w800,
                                fontSize: 22 * s,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Name banner text.
                      _place(
                        s,
                        x: 128,
                        y: 430,
                        w: 344,
                        h: 58,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              player.name,
                              maxLines: 1,
                              style: TextStyle(
                                color: _bannerInk,
                                fontWeight: FontWeight.w900,
                                fontSize: 26 * s,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Six stats, two columns astride the frame's divider.
                      _place(
                        s,
                        x: 84,
                        y: 516,
                        w: 432,
                        h: 188,
                        child: _StatsPanel(
                          ratings: r,
                          scale: s,
                          isGoalkeeper:
                              player.position?.group ==
                              PositionGroup.goalkeeper,
                        ),
                      ),

                      if (player.academicEligibilityApplicable)
                        // Academic-standing badge for school clubs only.
                        _place(
                          s,
                          x: 120,
                          y: 712,
                          w: 360,
                          h: 44,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _EligibilityBadge(
                                status: player.eligibility,
                                scale: s,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Places [child] in the frame's coordinate space, scaled to real pixels.
  Widget _place(
    double s, {
    required double x,
    required double y,
    required double w,
    required double h,
    required Widget child,
  }) {
    return Positioned(
      left: x * s,
      top: y * s,
      width: w * s,
      height: h * s,
      child: child,
    );
  }
}

/// The circular player photo, or a person icon when none is set.
class _Photo extends StatelessWidget {
  const _Photo({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return ClipOval(
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              // Decode at roster-card size rather than full resolution — the
              // grid shows many small photos (audit finding F10).
              cacheWidth: 300,
              errorBuilder: (context, error, stack) => const _PhotoFallback(),
            )
          : const _PhotoFallback(),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) =>
          Icon(Icons.person, color: Colors.white38, size: c.maxWidth * 0.62),
    );
  }
}

/// Two columns of three attributes each — the outfield six or, for a
/// goalkeeper, the GK six.
class _StatsPanel extends StatelessWidget {
  const _StatsPanel({
    required this.ratings,
    required this.scale,
    required this.isGoalkeeper,
  });

  final PlayerRatings ratings;
  final double scale;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    // Same "first three left, last three right" split as the outfield card,
    // applied to the GK six in their declared order (DIV/HAN/KIC/REF/SPD/POS).
    final left = isGoalkeeper
        ? [
            ('DIV', ratings.diving),
            ('HAN', ratings.handling),
            ('KIC', ratings.kicking),
          ]
        : [
            ('PAC', ratings.pace),
            ('SHO', ratings.shooting),
            ('PAS', ratings.passing),
          ];
    final right = isGoalkeeper
        ? [
            ('REF', ratings.reflexes),
            ('SPD', ratings.speed),
            ('POS', ratings.positioning),
          ]
        : [
            ('DRI', ratings.dribbling),
            ('DEF', ratings.defending),
            ('PHY', ratings.physical),
          ];
    return Row(
      children: [
        Expanded(
          child: _StatColumn(scale: scale, stats: left),
        ),
        Container(
          width: 2 * scale,
          margin: EdgeInsets.symmetric(vertical: 8 * scale),
          color: PlayerCard._gold.withValues(alpha: 0.4),
        ),
        Expanded(
          child: _StatColumn(scale: scale, stats: right),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.stats, required this.scale});

  final List<(String, int)> stats;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (label, value) in stats)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 30 * scale,
                  ),
                ),
                SizedBox(width: 6 * scale),
                Text(
                  label,
                  style: TextStyle(
                    color: PlayerCard._gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 20 * scale,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A translucent academic-standing pill sized for the dark card face.
class _EligibilityBadge extends StatelessWidget {
  const _EligibilityBadge({required this.status, required this.scale});

  final EligibilityStatus status;
  final double scale;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    switch (status) {
      case EligibilityStatus.eligible:
        color = const Color(0xFF8FE3A6);
        icon = Icons.check_circle;
        break;
      case EligibilityStatus.academicWarning:
        color = const Color(0xFFFFC65C);
        icon = Icons.warning_amber_rounded;
        break;
      case EligibilityStatus.notEligible:
        color = const Color(0xFFFF8A80);
        icon = Icons.cancel;
        break;
      case EligibilityStatus.pending:
        color = const Color(0xFFB0BEC5);
        icon = Icons.hourglass_bottom;
        break;
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 6 * scale,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(
          color: color.withValues(alpha: 0.7),
          width: 1.5 * scale,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16 * scale, color: color),
          SizedBox(width: 6 * scale),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15 * scale,
            ),
          ),
        ],
      ),
    );
  }
}
