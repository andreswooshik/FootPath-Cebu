import 'package:flutter/material.dart';

class CoordinatorInjuriesPlaceholderScreen extends StatelessWidget {
  const CoordinatorInjuriesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Injuries'),
    ),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Injury reports and confirmation requests will appear here.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
