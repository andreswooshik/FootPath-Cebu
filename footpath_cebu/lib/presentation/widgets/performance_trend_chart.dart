import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight 0–10 coach-rating trend with no chart-package dependency.
class PerformanceTrendChart extends StatelessWidget {
  const PerformanceTrendChart({
    super.key,
    required this.ratings,
    this.height = 160,
  });

  final List<double> ratings;
  final double height;

  @override
  Widget build(BuildContext context) {
    final values = ratings
        .map((value) => value.clamp(0, 10).toDouble())
        .toList();
    final description = values.isEmpty
        ? 'No performance trend available'
        : 'Coach ratings from oldest to newest: '
              '${values.map((value) => value.toStringAsFixed(1)).join(', ')}';
    return Semantics(
      label: description,
      image: true,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: _TrendPainter(
            values: values,
            lineColor: Theme.of(context).colorScheme.primary,
            gridColor: Theme.of(context).dividerColor,
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const top = 10.0;
    const bottom = 22.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - 8,
      size.height - bottom,
    );
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    for (final rating in [0, 5, 10]) {
      final y = chart.bottom - chart.height * rating / 10;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final label = TextPainter(
        text: TextSpan(
          text: '$rating',
          style: TextStyle(color: gridColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(2, y - label.height / 2));
    }

    if (values.isEmpty) return;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final path = Path();
    final divisor = math.max(1, values.length - 1);
    for (var index = 0; index < values.length; index++) {
      final x = chart.left + chart.width * index / divisor;
      final y = chart.bottom - chart.height * values[index] / 10;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, fillPaint);
    }
    canvas.drawPath(path, linePaint);

    final oldest = TextPainter(
      text: TextSpan(
        text: 'Older',
        style: TextStyle(color: gridColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    oldest.paint(canvas, Offset(chart.left, chart.bottom + 5));
    final latest = TextPainter(
      text: TextSpan(
        text: 'Latest',
        style: TextStyle(color: gridColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    latest.paint(canvas, Offset(chart.right - latest.width, chart.bottom + 5));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
