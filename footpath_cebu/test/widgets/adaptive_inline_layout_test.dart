import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/presentation/widgets/adaptive_inline_layout.dart';

Widget _app({required double width, required TextScaler textScaler}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: const AdaptiveInlineLayout(
              leading: Text('Section title', key: Key('leading')),
              trailing: FilledButton(
                key: Key('trailing'),
                onPressed: null,
                child: Text('Action'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('stays inline when width and text size allow it', (tester) async {
    await tester.pumpWidget(_app(width: 500, textScaler: TextScaler.noScaling));

    final leading = tester.getCenter(find.byKey(const Key('leading')));
    final trailing = tester.getCenter(find.byKey(const Key('trailing')));
    expect((leading.dy - trailing.dy).abs(), lessThan(1));
    expect(leading.dx, lessThan(trailing.dx));
  });

  testWidgets('stacks for compact width or enlarged text', (tester) async {
    await tester.pumpWidget(
      _app(width: 320, textScaler: const TextScaler.linear(2)),
    );

    final leading = tester.getCenter(find.byKey(const Key('leading')));
    final trailing = tester.getCenter(find.byKey(const Key('trailing')));
    expect(leading.dy, lessThan(trailing.dy));
    expect(tester.takeException(), isNull);
  });
}
