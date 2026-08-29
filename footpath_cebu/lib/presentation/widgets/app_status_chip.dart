import 'package:flutter/material.dart';

enum AppStatusTone { info, pending, success, warning, danger, neutral }

/// Shared semantic status treatment. The label and optional icon ensure that
/// status meaning never depends on colour alone.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.compact = true,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (foreground, background) = switch (tone) {
      AppStatusTone.info => (scheme.primary, scheme.primaryContainer),
      AppStatusTone.pending => (
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
      ),
      AppStatusTone.success => (
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
      AppStatusTone.warning => (
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
      ),
      AppStatusTone.danger => (scheme.error, scheme.errorContainer),
      AppStatusTone.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };

    return Chip(
      avatar: icon == null ? null : Icon(icon, color: foreground, size: 18),
      label: Text(label),
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      backgroundColor: background,
      side: BorderSide(color: foreground.withValues(alpha: 0.45)),
      visualDensity: compact ? VisualDensity.compact : null,
    );
  }
}
