import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/repositories/device_repository.dart';
import 'package:http/http.dart' as http;

/// Obtains the device's push token. Injected so the FCM plugin dependency stays
/// out of this layer — see [ApiDeviceRepository] for why.
typedef PushTokenProvider = Future<String?> Function();

/// Live device registration: obtains an FCM token via [tokenProvider] and POSTs
/// it to the Django backend (`/api/devices/`) with the signed-in user's
/// Firebase ID token, so the server can fan out notifications to this device.
///
/// The token source is injected rather than importing `firebase_messaging`
/// directly, because the current `firebase_messaging` release is incompatible
/// with the `firebase_core_platform_interface` that the pinned
/// `firebase_auth 6.5.4` requires. To enable real push once a compatible
/// `firebase_messaging` is pinned, pass a provider from the composition root:
///
/// ```dart
/// ApiDeviceRepository(() async {
///   await FirebaseMessaging.instance.requestPermission();
///   return FirebaseMessaging.instance.getToken();
/// });
/// ```
///
/// With no provider (the default today) registration is a logged no-op — the
/// app works fully, just without push, and the backend endpoint stays ready.
/// Every failure is swallowed and logged; push must never break login.
class ApiDeviceRepository implements DeviceRepository {
  ApiDeviceRepository([this._tokenProvider]);

  final PushTokenProvider? _tokenProvider;

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final idToken = await user.getIdToken();
    if (idToken == null) return;

    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/devices/'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': fcmToken, 'platform': _platform()}),
    );
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }
}
