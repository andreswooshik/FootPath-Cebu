import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/player.dart';

/// A six-axis radar (spider-web) chart of a player's attributes, drawn with a
/// [CustomPainter] so it needs no charting package. The filled polygon animates
/// from the centre outward the first time it's shown.
///
/// Axis order clockwise from the top mirrors [PlayerCard]'s two-column stat
/// panel so the two read as the same player: walk down the card's left column,
/// then back up its right column. Outfield: PAC, SHO, PAS (left, top→bottom),
/// then PHY, DEF, DRI (right, bottom→top). Goalkeeper: DIV, HAN, KIC (left),
/// then POS, SPD, REF (right, reversed) — the same rule applied to the GK
/// six's own left/right split (see `_StatsPanel` in player_card.dart).
class AttributeRadarChart extends StatelessWidget {
  const AttributeRadarChart({
    super.key,
    required this.ratings,
    required this.isGoalkeeper,
    this.fillColor,
    this.size = 220,
  });

  final PlayerRatings ratings;

  /// True to relabel the six axes to the GK set instead of the outfield six.
  final bool isGoalkeeper;

  /// Polygon colour; defaults to the theme primary.
  final Color? fillColor;
  final double size;

  static const _outfieldAxes = <String>[
    'PAC',
    'SHO',
    'PAS',
    'PHY',
    'DEF',
    'DRI',
  ];
  static const _gkAxes = <String>['DIV', 'HAN', 'KIC', 'POS', 'SPD', 'REF'];

  List<String> get _axes => isGoalkeeper ? _gkAxes : _outfieldAxes;

  List<double> get _values => isGoalkeeper
      ? [
          ratings.diving / 99,
          ratings.handling / 99,
          ratings.kicking / 99,
          ratings.positioning / 99,
          ratings.speed / 99,
          ratings.reflexes / 99,
        ]
      : [
          ratings.pace / 99,
          ratings.shooting / 99,
          ratings.passing / 99,
          ratings.physical / 99,
          ratings.defending / 99,
          ratings.dribbling / 99,
        ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = fillColor ?? cs.primary;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TweenAnimationBuilder<double>(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RadarPainter(
            values: _values,
            labels: _axes,
            progress: t,
            accent: accent,
            gridColor: cs.outlineVariant,
            labelColor: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.values,
    required this.labels,
    required this.progress,
    required this.accent,
    required this.gridColor,
    required this.labelColor,
  });

  final List<double> values;
  final List<String> labels;
  final double progress;
  final Color accent;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Leave a margin for the axis labels.
    final radius = math.min(size.width, size.height) / 2 - 26;
    final count = values.length;
    final step = (2 * math.pi) / count;
    // Start at the top (−90°).
    double angleAt(int i) => -math.pi / 2 + step * i;

    // Concentric grid rings (4 rings).
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor.withValues(alpha: 0.6);
    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final path = Path();
      for (var i = 0; i < count; i++) {
        final p =
            center + Offset(math.cos(angleAt(i)), math.sin(angleAt(i))) * r;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Spokes.
    for (var i = 0; i < count; i++) {
      final p =
          center + Offset(math.cos(angleAt(i)), math.sin(angleAt(i))) * radius;
      canvas.drawLine(center, p, gridPaint);
    }

    // Data polygon (animated outward via [progress]).
    final dataPath = Path();
    for (var i = 0; i < count; i++) {
      final v = (values[i].clamp(0.0, 1.0)) * progress;
      final p =
          center +
          Offset(math.cos(angleAt(i)), math.sin(angleAt(i))) * radius * v;
      i == 0 ? dataPath.moveTo(p.dx, p.dy) : dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(
      dataPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = accent.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );
    // Vertices.
    for (var i = 0; i < count; i++) {
      final v = (values[i].clamp(0.0, 1.0)) * progress;
      final p =
          center +
          Offset(math.cos(angleAt(i)), math.sin(angleAt(i))) * radius * v;
      canvas.drawCircle(p, 3, Paint()..color = accent);
    }

    // Axis labels.
    for (var i = 0; i < count; i++) {
      final p =
          center +
          Offset(math.cos(angleAt(i)), math.sin(angleAt(i))) * (radius + 16);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress || old.values != values || old.accent != accent;
}
