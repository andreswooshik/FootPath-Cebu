import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/presentation/screens/coach_matches_screen.dart';

void main() {
  testWidgets('coach match rows adapt to compact phones and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const CoachMatchesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Match Ratings'), findsOneWidget);
    expect(find.textContaining('Cebu United'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
