import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';

import 'firebase_options.dart';

/// Lets push-notification handlers surface a SnackBar without a widget
/// BuildContext. Wired to the app's [MaterialApp]; used once foreground FCM
/// message handling is enabled (see api_device_repository.dart).
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Whether to wire the in-memory mock repositories instead of the live
/// Firebase + Django backend.
///
/// A release build ALWAYS uses live data — the mock auth accepts a shared demo
/// password for any email, so it must never ship (audit finding F1). In debug,
/// mocks are the default for UI work; override with
/// `--dart-define=USE_MOCK=false` to run debug against the real backend.
bool get useMockData {
  if (kReleaseMode) return false;
  return const bool.fromEnvironment('USE_MOCK', defaultValue: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (useMockData) {
    ServiceLocator.initMock();
  } else {
    ServiceLocator.initFirebase();
  }

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
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
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
