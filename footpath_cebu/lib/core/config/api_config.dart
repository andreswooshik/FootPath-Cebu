import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  /// Overrides the base URL at build time, e.g.
  /// `--dart-define=API_BASE_URL=https://api.footpathcebu.com`. Lets a real
  /// device or a hosted backend work without editing code. Empty = use the
  /// per-platform localhost defaults below.
  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8000';
    // 10.0.2.2 is the Android emulator's loopback to the host machine.
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }
}
