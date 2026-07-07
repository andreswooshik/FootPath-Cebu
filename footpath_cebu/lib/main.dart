import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? setupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Missing firebase_options.dart config (run `flutterfire configure`) —
    // show instructions instead of crashing on startup.
    setupError = '$e';
  }
  runApp(FootPathApp(setupError: setupError));
}

class FootPathApp extends StatelessWidget {
  const FootPathApp({super.key, this.setupError});

  final String? setupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FootPath Cebu',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: setupError == null
          ? const LoginScreen()
          : _SetupErrorScreen(message: setupError!),
    );
  }
}

class _SetupErrorScreen extends StatelessWidget {
  const _SetupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.build_circle_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'Firebase setup required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
