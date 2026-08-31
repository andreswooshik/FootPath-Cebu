import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// FUT-style player identity card using the five independent development
/// domains. The frame is decorative; no combined overall score is calculated
/// or displayed.
class PlayerCard extends StatefulWidget {
  const PlayerCard({super.key, required this.player, this.onTap});

  final Player player;

  /// Opens the full player profile from the action on the legacy side.
  /// Tapping the card itself flips between the two faces.
  final VoidCallback? onTap;

  static const double _canvasW = 600;
  static const double _canvasH = 850;
  static const Color _gold = Color(0xFFE7C86A);
  static const Color _bannerInk = Color(0xFF072A1F);

  @override
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _flip = CurvedAnimation(
    parent: _flipController,
    curve: Curves.easeInOutCubic,
  );
  bool _showingLegacy = false;

  @override
  void didUpdateWidget(covariant PlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.id == widget.player.id) return;
    _flipController.value = 0;
    _showingLegacy = false;
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleFace() {
    setState(() => _showingLegacy = !_showingLegacy);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _flipController.value = _showingLegacy ? 1 : 0;
      return;
    }
    if (_showingLegacy) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final assessment = player.developmentAssessment;
    final position = player.position?.labelWithCode ?? 'Position not assigned';
    final side = _showingLegacy
        ? (player.position?.group == PositionGroup.goalkeeper
              ? 'goalkeeper attributes shown'
              : 'outfield attributes shown')
        : (assessment == null
              ? 'assessment side, not assessed yet'
              : 'assessment side, five domains rated');
    return MotionPress(
      child: Semantics(
        container: true,
        button: true,
        label: [player.name, position, side].join(', '),
        hint: _showingLegacy
            ? 'Tap to show assessment domains'
            : 'Tap to show legacy attributes',
        customSemanticsActions: widget.onTap == null
            ? null
            : {
                const CustomSemanticsAction(label: 'View player profile'):
                    widget.onTap!,
              },
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _toggleFace,
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: PlayerCard._canvasW / PlayerCard._canvasH,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = constraints.maxWidth / PlayerCard._canvasW;
                  return AnimatedBuilder(
                    animation: _flip,
                    builder: (context, _) {
                      final angle = _flip.value * math.pi;
                      final showingBack = angle > math.pi / 2;
                      Widget face = showingBack
                          ? _LegacyAttributesFace(
                              player: player,
                              scale: scale,
                              onViewProfile: widget.onTap,
                            )
                          : _AssessmentFace(player: player, scale: scale);
                      if (showingBack) {
                        face = Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(math.pi),
                          child: face,
                        );
                      }
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(angle),
                        child: face,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssessmentFace extends StatelessWidget {
  const _AssessmentFace({required this.player, required this.scale});

  final Player player;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final assessment = player.developmentAssessment;
    return _CardFrame(
      player: player,
      scale: scale,
      children: [
        _place(
          scale,
          x: 110,
          y: 493,
          w: 380,
          h: 28,
          child: Center(
            child: Text(
              'ASSESSMENT DOMAINS · 1–5',
              style: TextStyle(
                color: PlayerCard._gold,
                fontWeight: FontWeight.w800,
                fontSize: 15 * scale,
                letterSpacing: 1.2 * scale,
              ),
            ),
          ),
        ),
        _place(
          scale,
          x: 84,
          y: 526,
          w: 432,
          h: 162,
          child: _DevelopmentPanel(
            domainScores: assessment?.domainScores,
            scale: scale,
          ),
        ),
        _place(
          scale,
          x: 112,
          y: 692,
          w: 376,
          h: 30,
          child: Center(
            child: Text(
              assessment == null ? 'AWAITING ASSESSMENT' : '5 DOMAINS ASSESSED',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 14 * scale,
                letterSpacing: 0.8 * scale,
              ),
            ),
          ),
        ),
        if (player.academicEligibilityApplicable)
          _place(
            scale,
            x: 120,
            y: 728,
            w: 360,
            h: 44,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _EligibilityBadge(
                  status: player.eligibility,
                  scale: scale,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LegacyAttributesFace extends StatelessWidget {
  const _LegacyAttributesFace({
    required this.player,
    required this.scale,
    required this.onViewProfile,
  });

  final Player player;
  final double scale;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    final goalkeeper = player.position?.group == PositionGroup.goalkeeper;
    return _CardFrame(
      player: player,
      scale: scale,
      children: [
        _place(
          scale,
          x: 92,
          y: 493,
          w: 416,
          h: 28,
          child: Center(
            child: Text(
              goalkeeper
                  ? 'GOALKEEPER ATTRIBUTES · 0–99'
                  : 'OUTFIELD ATTRIBUTES · 0–99',
              style: TextStyle(
                color: PlayerCard._gold,
                fontWeight: FontWeight.w800,
                fontSize: 15 * scale,
                letterSpacing: 1.1 * scale,
              ),
            ),
          ),
        ),
        _place(
          scale,
          x: 84,
          y: 526,
          w: 432,
          h: 162,
          child: _LegacyAttributePanel(
            ratings: player.ratings,
            goalkeeper: goalkeeper,
            scale: scale,
          ),
        ),
        if (onViewProfile == null)
          _place(
            scale,
            x: 112,
            y: 704,
            w: 376,
            h: 30,
            child: Center(
              child: Text(
                'TAP CARD TO RETURN',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 14 * scale,
                  letterSpacing: 0.8 * scale,
                ),
              ),
            ),
          ),
        if (onViewProfile != null)
          _place(
            scale,
            x: 160,
            y: 696,
            w: 280,
            h: 44,
            child: TextButton(
              key: ValueKey('view-profile-${player.id}'),
              onPressed: onViewProfile,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                backgroundColor: PlayerCard._gold.withValues(alpha: 0.16),
                side: BorderSide(
                  color: PlayerCard._gold.withValues(alpha: 0.7),
                  width: 1.2 * scale,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22 * scale),
                ),
              ),
              child: Text(
                'VIEW PROFILE',
                style: TextStyle(
                  color: PlayerCard._gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 15 * scale,
                  letterSpacing: 0.8 * scale,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.player,
    required this.scale,
    required this.children,
  });

  final Player player;
  final double scale;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: SvgPicture.asset(
          'assets/cards/card_frame.svg',
          fit: BoxFit.fill,
        ),
      ),
      _place(
        scale,
        x: 170,
        y: 140,
        w: 260,
        h: 260,
        child: _Photo(photoUrl: player.photoUrl),
      ),
      _place(
        scale,
        x: 44,
        y: 156,
        w: 150,
        h: 82,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              player.position?.code ?? '--',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 50 * scale,
                height: 1,
              ),
            ),
          ),
        ),
      ),
      _place(
        scale,
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
                color: PlayerCard._bannerInk,
                fontWeight: FontWeight.w900,
                fontSize: 26 * scale,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
      ...children,
    ],
  );
}

Widget _place(
  double scale, {
  required double x,
  required double y,
  required double w,
  required double h,
  required Widget child,
}) => Positioned(
  left: x * scale,
  top: y * scale,
  width: w * scale,
  height: h * scale,
  child: child,
);

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Icon(
      Icons.person,
      color: Colors.white38,
      size: constraints.maxWidth * 0.62,
    ),
  );
}

class _DevelopmentPanel extends StatelessWidget {
  const _DevelopmentPanel({required this.domainScores, required this.scale});

  final Map<String, double?>? domainScores;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final left = [
      ('TEC', 'technical'),
      ('TAC', 'tactical'),
      ('PHYS', 'physical'),
    ];
    final right = [('MEN', 'mental'), ('VAL', 'socialValues')];
    return Row(
      children: [
        Expanded(
          child: _DomainColumn(
            domains: left,
            scores: domainScores,
            scale: scale,
          ),
        ),
        Container(
          width: 2 * scale,
          margin: EdgeInsets.symmetric(vertical: 8 * scale),
          color: PlayerCard._gold.withValues(alpha: 0.4),
        ),
        Expanded(
          child: _DomainColumn(
            domains: right,
            scores: domainScores,
            scale: scale,
          ),
        ),
      ],
    );
  }
}

class _DomainColumn extends StatelessWidget {
  const _DomainColumn({
    required this.domains,
    required this.scores,
    required this.scale,
  });

  final List<(String, String)> domains;
  final Map<String, double?>? scores;
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final (label, key) in domains)
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                scores?[key]?.toStringAsFixed(1) ?? '—',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 28 * scale,
                ),
              ),
              SizedBox(width: 7 * scale),
              Text(
                label,
                style: TextStyle(
                  color: PlayerCard._gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 18 * scale,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _LegacyAttributePanel extends StatelessWidget {
  const _LegacyAttributePanel({
    required this.ratings,
    required this.goalkeeper,
    required this.scale,
  });

  final PlayerRatings ratings;
  final bool goalkeeper;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final left = goalkeeper
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
    final right = goalkeeper
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
          child: _LegacyAttributeColumn(values: left, scale: scale),
        ),
        Container(
          width: 2 * scale,
          margin: EdgeInsets.symmetric(vertical: 8 * scale),
          color: PlayerCard._gold.withValues(alpha: 0.4),
        ),
        Expanded(
          child: _LegacyAttributeColumn(values: right, scale: scale),
        ),
      ],
    );
  }
}

class _LegacyAttributeColumn extends StatelessWidget {
  const _LegacyAttributeColumn({required this.values, required this.scale});

  final List<(String, int)> values;
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final (label, value) in values)
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
                  fontSize: 28 * scale,
                ),
              ),
              SizedBox(width: 7 * scale),
              Text(
                label,
                style: TextStyle(
                  color: PlayerCard._gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 18 * scale,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

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
      case EligibilityStatus.academicWarning:
        color = const Color(0xFFFFC65C);
        icon = Icons.warning_amber_rounded;
      case EligibilityStatus.notEligible:
        color = const Color(0xFFFF8A80);
        icon = Icons.cancel;
      case EligibilityStatus.pending:
        color = const Color(0xFFB0BEC5);
        icon = Icons.hourglass_bottom;
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
