import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/widgets/sign_out_confirmation.dart';

void main() {
  testWidgets('sign out requires explicit confirmation', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmSignOut(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
