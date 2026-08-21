import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/repositories/device_repository.dart';

/// Obtains the device's push token. Injected so the FCM plugin dependency stays
/// out of this layer — see [ApiDeviceRepository] for why.
typedef PushTokenProvider = Future<String?> Function();

/// Live device registration: obtains an FCM token via [tokenProvider] and POSTs
/// it to the Django backend (`/api/devices/`) with the signed-in user's
/// Firebase ID token, so the server can fan out notifications to this device.
///
/// The token source is injected rather than importing `firebase_messaging`
/// directly so plugin and permission concerns stay in the composition root and
/// this adapter remains deterministic in unit tests. The live provider requests
/// notification permission and reads the current FCM token:
///
/// ```dart
/// ApiDeviceRepository(() async {
///   await FirebaseMessaging.instance.requestPermission();
///   return FirebaseMessaging.instance.getToken();
/// });
/// ```
///
/// A null provider remains a supported no-op for isolated tests or alternate
/// builds. Live wiring supplies it from `core/di/providers.dart`. Every failure
/// is swallowed and logged; push must never break login or sign-out.
class ApiDeviceRepository implements DeviceRepository {
  ApiDeviceRepository([this._tokenProvider, AuthenticatedApiClient? api])
    : _api = api ?? AuthenticatedApiClient.shared;

  final PushTokenProvider? _tokenProvider;
  final AuthenticatedApiClient _api;
  static const _tokenTimeout = Duration(seconds: 5);

  @override
  Future<void> registerCurrentDevice() async {
    final provider = _tokenProvider;
    if (provider == null) {
      debugPrint(
        'Push token provider not configured; skipping device registration.',
      );
      return;
    }
    try {
      final fcmToken = await provider();
      if (fcmToken == null || fcmToken.isEmpty) return;
      await _sendToken(fcmToken);
    } catch (e) {
      debugPrint('Device registration skipped: $e');
    }
  }

  Future<void> _sendToken(String fcmToken) async {
    await _api.post(
      '/api/devices/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': fcmToken, 'platform': _platform()}),
      expectedStatuses: const {200, 201, 204},
    );
  }

  @override
  Future<void> unregisterCurrentDevice() async {
    final provider = _tokenProvider;
    if (provider == null) return;
    try {
      final fcmToken = await provider().timeout(_tokenTimeout);
      if (fcmToken == null || fcmToken.isEmpty) return;
      await _api.delete(
        '/api/devices/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': fcmToken}),
        expectedStatuses: const {200, 204},
      );
    } catch (error) {
      debugPrint('Device unregister skipped: $error');
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }
}
