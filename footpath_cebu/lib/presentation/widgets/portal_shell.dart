import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';

/// A tab shell for the role portals.
///
/// The tab pages stay mounted in an [IndexedStack], so scroll positions and
/// in-progress tab state survive a destination change. The active stack gets
/// a declarative fade/scale entrance instead of a full route transition
/// because bottom-nav destinations are peers, not a parent/child path.
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

class _PortalShellState extends State<PortalShell> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant PortalShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pages.isEmpty) return;
    if (_selectedIndex >= widget.pages.length) {
      _selectedIndex = widget.pages.length - 1;
    }
  }

  void _selectTab(int index) {
    if (index == _selectedIndex || index < 0 || index >= widget.pages.length) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.pages.isNotEmpty, 'PortalShell requires at least one page.');

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget tabBody = IndexedStack(
      index: _selectedIndex,
      children: widget.pages,
    );
    if (!reduceMotion) {
      tabBody = tabBody
          .animate(target: _selectedIndex == 0 ? 0 : 1)
          .fade(
            begin: 0.84,
            end: 1,
            duration: AppMotion.microDuration,
            curve: Curves.easeOutCubic,
          )
          .scale(
            begin: const Offset(0.985, 0.985),
            end: const Offset(1, 1),
            duration: AppMotion.microDuration,
            curve: Curves.easeOutCubic,
          );
    }

    return Scaffold(
      body: tabBody,
      bottomNavigationBar: widget.showNavigation
          ? widget.navigationBarBuilder(_selectedIndex, _selectTab)
          : null,
    );
  }
}
