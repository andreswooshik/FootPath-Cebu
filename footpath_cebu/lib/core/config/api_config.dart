import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class ApiConfig {
  /// Overrides the base URL at build time, e.g.
  /// `--dart-define=API_BASE_URL=https://api.footpathcebu.com`. Lets a real
  /// device or a hosted backend work without editing code. Empty = use the
  /// per-platform localhost defaults below.
  static const _override = String.fromEnvironment('API_BASE_URL');
  static const _allowedReleaseHost = String.fromEnvironment('API_ALLOWED_HOST');

  static String get baseUrl {
    final url = _override.isNotEmpty
        ? _override
        : kIsWeb
        ? 'http://localhost:8000'
        : Platform.isAndroid
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.scheme.isEmpty) {
      throw StateError('API_BASE_URL must be a valid absolute URL.');
    }
    if (kReleaseMode) {
      if (uri.scheme != 'https' ||
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '10.0.2.2' ||
          (_allowedReleaseHost.isNotEmpty && uri.host != _allowedReleaseHost)) {
        throw StateError(
          'Release builds require an allow-listed HTTPS API_BASE_URL.',
        );
      }
    }
    return url.replaceFirst(RegExp(r'/$'), '');
  }
}
