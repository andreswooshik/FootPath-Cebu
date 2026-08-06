import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Shared motion timings for the FootPath Cebu UI.
class AppMotion {
  AppMotion._();

  static const screenDuration = Duration(milliseconds: 280);
  static const listDuration = Duration(milliseconds: 240);
  static const microDuration = Duration(milliseconds: 140);
  static const listInterval = Duration(milliseconds: 45);
}

/// Declarative, reduced-motion-aware animation recipes used by presentation
/// widgets. These extensions contain no business state and do not create
/// controllers, so Riverpod rebuilds can safely reuse the same Animate state.
extension AppMotionExtensions on Widget {
  Widget animateScreenEntrance({Duration? delay}) => Builder(
    builder: (context) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return this;
      }
      return animate(delay: delay)
          .fadeIn(
            duration: AppMotion.screenDuration,
            curve: Curves.easeOutCubic,
          )
          .slideY(
            begin: 0.025,
            end: 0,
            duration: AppMotion.screenDuration,
            curve: Curves.fastOutSlowIn,
          );
    },
  );

  Widget animateListItem({required Key key, int index = 0}) => Builder(
    builder: (context) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return KeyedSubtree(key: key, child: this);
      }
      return animate(key: key, delay: AppMotion.listInterval * index)
          .fadeIn(duration: AppMotion.listDuration, curve: Curves.easeOutCubic)
          .slideY(
            begin: 0.035,
            end: 0,
            duration: AppMotion.listDuration,
            curve: Curves.easeOutCubic,
          );
    },
  );

  Widget shimmerLoading({bool repeat = true}) => Builder(
    builder: (context) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return this;
      }
      final shimmer = repeat
          ? animate(onPlay: (controller) => controller.repeat())
          : animate();
      return shimmer.shimmer(
        duration: const Duration(milliseconds: 1200),
        color: Colors.white.withValues(alpha: 0.35),
      );
    },
  );
}

/// Adds a small press scale while preserving the child's own gesture and
/// ink semantics. This is intentionally a local UI state, not provider state.
class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child});

  final Widget child;

  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: widget.child
          .animate(target: _pressed ? 1 : 0)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(0.97, 0.97),
            duration: AppMotion.microDuration,
            curve: Curves.easeOutCubic,
          ),
    );
  }
}

/// A lightweight skeleton surface for asynchronous content.
class MotionSkeleton extends StatelessWidget {
  const MotionSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ).shimmerLoading(repeat: false);
  }
}

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
