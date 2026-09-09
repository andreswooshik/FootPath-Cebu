import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/presentation/widgets/portal_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/portal_shell.dart';

void main() {
  testWidgets('uses phone navigation without overflow at enlarged text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PortalShell(
          pages: const [
            Center(child: Text('Dashboard page')),
            Center(child: Text('Schedule page')),
            Center(child: Text('Progress page')),
            Center(child: Text('Profile page')),
          ],
          navigationBarBuilder: (selectedIndex, onSelected) => PortalBottomNav(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
          ),
          navigationRailBuilder: (selectedIndex, onSelected, extended) =>
              PortalNavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                extended: extended,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Dashboard page'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule page'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('uses compact navigation in phone landscape', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: PortalShell(
          pages: const [
            Center(child: Text('Dashboard page')),
            Center(child: Text('Schedule page')),
          ],
          navigationBarBuilder: (selectedIndex, onSelected) => PortalBottomNav(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
          ),
          navigationRailBuilder: (selectedIndex, onSelected, extended) =>
              PortalNavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                extended: extended,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
