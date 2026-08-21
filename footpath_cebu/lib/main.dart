import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/notification_destination.dart';
import 'package:footpath_cebu/presentation/providers/notification_providers.dart';
import 'package:footpath_cebu/presentation/screens/notification_destination_screen.dart';
import 'package:footpath_cebu/presentation/screens/notification_inbox_screen.dart';
import 'package:footpath_cebu/presentation/screens/session_bootstrap_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';

import 'firebase_options.dart';

/// Lets push-notification handlers surface a SnackBar without a widget
/// BuildContext. Wired to the app's [MaterialApp]; used once foreground FCM
/// message handling is enabled (see api_device_repository.dart).
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

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

class FootPathApp extends ConsumerStatefulWidget {
  const FootPathApp({super.key, this.setupError});

  final String? setupError;

  @override
  ConsumerState<FootPathApp> createState() => _FootPathAppState();
}

class _FootPathAppState extends ConsumerState<FootPathApp> {
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.setupError == null && !useMockData) {
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(_openMessage(message)),
      );
      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(ref.read(registerDeviceProvider)()),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openInitialMessage());
      });
    }
  }

  @override
  void dispose() {
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    _tokenSubscription?.cancel();
    super.dispose();
  }

  void _refreshInbox() {
    ref.invalidate(notificationsProvider);
    ref.invalidate(notificationUnreadCountProvider);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _refreshInbox();
    final title =
        message.notification?.title ??
        message.data['title'] ??
        'New notification';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(body.isEmpty ? '$title' : '$title\n$body'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => unawaited(_openMessage(message)),
          ),
        ),
      );
  }

  Future<void> _openInitialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) await _openMessage(message);
  }

  Future<void> _openMessage(RemoteMessage message) async {
    _refreshInbox();
    if (FirebaseAuth.instance.currentUser == null) return;
    final request = NotificationOpenRequest.fromData(
      message.data,
      sourceMessageId: message.messageId,
    );
    await ref.read(notificationNavigationControllerProvider).open(request, (
      resolved,
    ) async {
      var navigator = appNavigatorKey.currentState;
      if (navigator == null) {
        await WidgetsBinding.instance.endOfFrame;
        navigator = appNavigatorKey.currentState;
      }
      if (navigator == null || !navigator.mounted) return;

      final profile = resolved.profile;
      final destination = resolved.destination;
      if (profile == null ||
          destination.kind == NotificationDestinationKind.inbox) {
        await navigator.push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: '/notifications'),
            builder: (_) => NotificationInboxScreen(
              focusNotificationId: request.notificationId,
              focusType: request.type,
              focusSessionId: request.sessionId,
              focusPlayerId: request.playerId,
            ),
          ),
        );
        return;
      }
      await navigator.push<void>(
        MaterialPageRoute(
          settings: RouteSettings(
            name: '/notifications/${destination.kind.name}',
          ),
          builder: (_) => NotificationDestinationScreen(
            profile: profile,
            destination: destination,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FootPath Cebu',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: widget.setupError == null
          ? const SessionBootstrapScreen()
          : _SetupErrorScreen(message: widget.setupError!),
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
