import 'package:flutter/material.dart';

/// A tab shell for the role portals.
///
/// The tab pages stay mounted in an [IndexedStack], so scroll positions and
/// in-progress tab state survive a destination change. The active stack gets
/// a short fade/scale entrance instead of a full route transition because
/// bottom-nav destinations are peers, not a parent/child navigation path.
class PortalShell extends StatefulWidget {
  const PortalShell({
    super.key,
    required this.pages,
    required this.navigationBarBuilder,
    this.showNavigation = true,
  });

  final List<Widget> pages;
  final Widget Function(int selectedIndex, ValueChanged<int> onSelected)
  navigationBarBuilder;
  final bool showNavigation;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell>
    with SingleTickerProviderStateMixin {
  static const _transitionDuration = Duration(milliseconds: 200);

  late final AnimationController _transitionController = AnimationController(
    vsync: this,
    duration: _transitionDuration,
    value: 1,
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _transitionController,
    curve: Curves.easeOutCubic,
  ).drive(Tween(begin: 0.84, end: 1.0));

  late final Animation<double> _scale = CurvedAnimation(
    parent: _transitionController,
    curve: Curves.easeOutCubic,
  ).drive(Tween(begin: 0.985, end: 1.0));

  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant PortalShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pages.isEmpty) return;
    if (_selectedIndex >= widget.pages.length) {
      _selectedIndex = widget.pages.length - 1;
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _selectedIndex || index < 0 || index >= widget.pages.length) {
      return;
    }

    setState(() => _selectedIndex = index);

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _transitionController.value = 1;
    } else {
      _transitionController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.pages.isNotEmpty, 'PortalShell requires at least one page.');

    return Scaffold(
      body: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.topCenter,
          child: IndexedStack(index: _selectedIndex, children: widget.pages),
        ),
      ),
      bottomNavigationBar: widget.showNavigation
          ? widget.navigationBarBuilder(_selectedIndex, _selectTab)
          : null,
    );
  }
}
