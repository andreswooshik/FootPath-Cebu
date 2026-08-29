import 'package:flutter/material.dart';

/// Presents management forms as a keyboard-safe sheet on phones and a
/// constrained dialog on tablets. The form may close itself with
/// `Navigator.pop`, regardless of presentation style.
Future<T?> showAdaptiveFormModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 640,
  double? phoneHeightFactor,
}) {
  if (MediaQuery.sizeOf(context).width < 720) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: phoneHeightFactor,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: builder(sheetContext),
        ),
      ),
    );
  }

  return showDialog<T>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
        ),
        child: builder(dialogContext),
      ),
    ),
  );
}
