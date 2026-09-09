import 'package:flutter/material.dart';

/// Shared presentation policy for deciding when horizontal content should
/// become vertical on a narrow viewport or at an enlarged system text size.
abstract final class AdaptiveLayoutPolicy {
  static const double compactWidth = 360;
  static const double enlargedTextScale = 1.3;

  static bool shouldStack(
    BuildContext context,
    double availableWidth, {
    double widthBreakpoint = compactWidth,
    double textScaleBreakpoint = enlargedTextScale,
  }) =>
      availableWidth < widthBreakpoint ||
      MediaQuery.textScalerOf(context).scale(1) > textScaleBreakpoint;
}

/// Places related leading and trailing content in one row when space allows,
/// and stacks both at full width on compact or enlarged-text layouts.
class AdaptiveInlineLayout extends StatelessWidget {
  const AdaptiveInlineLayout({
    super.key,
    required this.leading,
    required this.trailing,
    this.spacing = 12,
    this.inlineTrailingWidth,
    this.widthBreakpoint = AdaptiveLayoutPolicy.compactWidth,
    this.textScaleBreakpoint = AdaptiveLayoutPolicy.enlargedTextScale,
  });

  final Widget leading;
  final Widget trailing;
  final double spacing;

  /// A fixed trailing width for action-style layouts. When null, the trailing
  /// content takes the remaining inline width instead.
  final double? inlineTrailingWidth;
  final double widthBreakpoint;
  final double textScaleBreakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (AdaptiveLayoutPolicy.shouldStack(
        context,
        constraints.maxWidth,
        widthBreakpoint: widthBreakpoint,
        textScaleBreakpoint: textScaleBreakpoint,
      )) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leading,
            SizedBox(height: spacing),
            trailing,
          ],
        );
      }

      final trailingWidth = inlineTrailingWidth;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: trailingWidth == null
            ? [leading, SizedBox(width: spacing), Expanded(child: trailing)]
            : [
                Expanded(child: leading),
                SizedBox(width: spacing),
                SizedBox(width: trailingWidth, child: trailing),
              ],
      );
    },
  );
}
