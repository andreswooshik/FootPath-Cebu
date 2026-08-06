import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/screens/session_bootstrap_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';

import 'firebase_options.dart';

/// Lets push-notification handlers surface a SnackBar without a widget
/// BuildContext. Wired to the app's [MaterialApp]; used once foreground FCM
/// message handling is enabled (see api_device_repository.dart).
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

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

  // ProviderScope is the composition root's container: every repository and
  // use-case provider (core/di/providers.dart) lives inside it, and tests
  // swap implementations by overriding providers on their own scope.
  runApp(ProviderScope(child: FootPathApp(setupError: setupError)));
}

class FootPathApp extends StatelessWidget {
  const FootPathApp({super.key, this.setupError});

  final String? setupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FootPath Cebu',
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: setupError == null
          ? const SessionBootstrapScreen()
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
