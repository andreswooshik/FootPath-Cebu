import 'package:flutter/material.dart';

/// A tear-away calendar page: a coloured header strip with the month, a big
/// day number, and the weekday — the little "date block" you'd rip off a desk
/// calendar. Used on schedule cards to make dates feel tangible and playful.
class TearAwayDate extends StatelessWidget {
  const TearAwayDate({
    super.key,
    required this.date,
    this.headerColor,
    this.width = 64,
  });

  final DateTime date;

  /// The month-strip colour; defaults to the theme's tertiary (orange).
  final Color? headerColor;
  final double width;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  static const _weekdays = [
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final header = headerColor ?? cs.tertiary;
    // Pick black or white by whichever contrasts more with the header. The
    // usual brightness heuristic picks white on coral (~3.9:1, below AA for
    // the small month label), whereas black on coral clears AA (~5.4:1).
    final onHeader = _readableOn(header);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month strip with two "binding rings".
          Container(
            width: double.infinity,
            color: header,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    2,
                    (_) => Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: onHeader.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _months[date.month - 1],
                  style: TextStyle(
                    color: onHeader,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  _weekdays[date.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Black or white, whichever has the higher WCAG contrast against [background].
/// Prefers the choice that actually reads, rather than a lightness threshold
/// that can land just under the AA minimum on mid-tone brand colours.
Color _readableOn(Color background) {
  final l = background.computeLuminance();
  final whiteContrast = 1.05 / (l + 0.05);
  final blackContrast = (l + 0.05) / 0.05;
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}
