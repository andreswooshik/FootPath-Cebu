import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight interactive trend chart with no chart-package dependency.
///
/// The caller supplies chronological values and human-readable point labels.
/// Touching or hovering near a point reveals its label and exact value.
class PerformanceTrendChart extends StatefulWidget {
  const PerformanceTrendChart({
    super.key,
    required this.ratings,
    this.height = 176,
    this.maxValue = 10,
    this.pointLabels = const [],
    this.metricLabel = 'Match Rating',
  });

  final List<double?> ratings;
  final double height;
  final double maxValue;
  final List<String> pointLabels;
  final String metricLabel;

  @override
  State<PerformanceTrendChart> createState() => _PerformanceTrendChartState();
}

class _PerformanceTrendChartState extends State<PerformanceTrendChart> {
  int? _selectedIndex;

  void _selectPoint(Offset position, double width) {
    if (widget.ratings.isEmpty) return;
    const left = 32.0;
    final chartWidth = math.max(1.0, width - left - 8);
    final fraction = ((position.dx - left) / chartWidth).clamp(0.0, 1.0);
    final index = widget.ratings.length == 1
        ? 0
        : (fraction * (widget.ratings.length - 1)).round();
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final safeMax = widget.maxValue <= 0 ? 1.0 : widget.maxValue;
    final values = widget.ratings
        .map((value) => value?.clamp(0, safeMax).toDouble())
        .toList(growable: false);
    final description = values.isEmpty
        ? 'No ${widget.metricLabel.toLowerCase()} trend available'
        : '${widget.metricLabel} from oldest to newest: '
              '${List.generate(values.length, (index) {
                final value = values[index];
                final point = index < widget.pointLabels.length ? '${widget.pointLabels[index]}: ' : '';
                return '$point${value?.toStringAsFixed(1) ?? 'missing'}';
              }).join(', ')}';

    return Semantics(
      label: description,
      image: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final selected = _selectedIndex;
          final selectedValue = selected == null || selected >= values.length
              ? null
              : values[selected];
          final selectedLabel = selected == null
              ? null
              : selected < widget.pointLabels.length
              ? widget.pointLabels[selected]
              : 'Match ${selected + 1}';
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (event) =>
                _selectPoint(event.localPosition, constraints.maxWidth),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _selectPoint(details.localPosition, constraints.maxWidth),
              child: SizedBox(
                width: double.infinity,
                height: widget.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrendPainter(
                          values: values,
                          pointLabels: widget.pointLabels,
                          selectedIndex: selected,
                          maxValue: safeMax,
                          lineColor: Theme.of(context).colorScheme.primary,
                          gridColor: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    if (selectedLabel != null)
                      Positioned(
                        top: 4,
                        right: 8,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const Key('trendTooltip'),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.35),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 6,
                                  color: Color(0x22000000),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                '$selectedLabel  ·  '
                                '${selectedValue?.toStringAsFixed(1) ?? 'Not recorded'}',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.pointLabels,
    required this.selectedIndex,
    required this.lineColor,
    required this.gridColor,
    required this.maxValue,
  });

  final List<double?> values;
  final List<String> pointLabels;
  final int? selectedIndex;
  final double maxValue;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 32.0;
    const top = 12.0;
    const bottom = 30.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - 8,
      size.height - bottom,
    );
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    for (final rating in [0.0, maxValue / 2, maxValue]) {
      final y = chart.bottom - chart.height * rating / maxValue;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final label = TextPainter(
        text: TextSpan(
          text: rating == rating.roundToDouble()
              ? '${rating.round()}'
              : rating.toStringAsFixed(1),
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
    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final selectedPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final path = Path();
    final divisor = math.max(1, values.length - 1);
    var segmentStarted = false;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == null) {
        segmentStarted = false;
        continue;
      }
      final x = chart.left + chart.width * index / divisor;
      final y = chart.bottom - chart.height * value / maxValue;
      if (!segmentStarted) {
        path.moveTo(x, y);
        segmentStarted = true;
      } else {
        path.lineTo(x, y);
      }
      if (selectedIndex == index) {
        canvas.drawCircle(Offset(x, y), 10, selectedPaint);
      }
      canvas.drawCircle(
        Offset(x, y),
        selectedIndex == index ? 5 : 4,
        pointPaint,
      );
    }
    canvas.drawPath(path, linePaint);

    void paintPointLabel(int index, TextAlign align) {
      if (index < 0 || index >= pointLabels.length) return;
      final value = pointLabels[index];
      if (value.trim().isEmpty) return;
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: gridColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout(maxWidth: math.max(64, chart.width / 2));
      final x = values.length == 1
          ? chart.center.dx - painter.width / 2
          : index == 0
          ? chart.left
          : chart.right - painter.width;
      painter.paint(canvas, Offset(x, chart.bottom + 7));
    }

    if (values.length == 1) {
      paintPointLabel(0, TextAlign.center);
    } else {
      paintPointLabel(0, TextAlign.left);
      paintPointLabel(values.length - 1, TextAlign.right);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.pointLabels != pointLabels ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
