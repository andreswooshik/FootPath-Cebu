import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';

/// Shared skeleton state for async screen content. Keeping the placeholder
/// shape stable prevents loading-to-data layout jumps while providers resolve.
class DashboardLoadingState extends StatelessWidget {
  const DashboardLoadingState({
    super.key,
    this.compact = false,
    this.shrinkWrap = false,
  });

  final bool compact;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        MotionSkeleton(height: compact ? 18 : 28, width: compact ? 180 : 240),
        const SizedBox(height: 16),
        for (var i = 0; i < (compact ? 3 : 5); i++) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const MotionSkeleton(width: 48, height: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MotionSkeleton(width: 120 + (i * 20).toDouble()),
                        const SizedBox(height: 10),
                        const MotionSkeleton(width: 180, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i != (compact ? 2 : 4)) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Shared error state for dashboard screens: an icon, a message, and a retry
/// button (typically wired to `ref.invalidate` on the failed provider).
class DashboardErrorState extends StatelessWidget {
  const DashboardErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            MotionPress(
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared empty-state content for dashboard and management lists.
///
/// The surrounding screen owns scrolling so pull-to-refresh remains available.
class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 32 : 72),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: compact ? 48 : 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
