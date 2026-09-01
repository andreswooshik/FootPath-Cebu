import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/data/local/api_get_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// The stable identity used for one request and its owner-scoped cache lookup.
class ApiIdentity {
  const ApiIdentity({required this.uid, required this.getIdToken});

  final String uid;
  final Future<String?> Function(bool forceRefresh) getIdToken;
}

typedef ApiIdentityProvider = ApiIdentity? Function();

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// No authenticated Firebase identity/token was available.
class ApiAuthenticationException extends ApiException {
  const ApiAuthenticationException(super.message);
}

/// The request did not receive an HTTP response (socket/client/timeout only).
class ApiNetworkException extends ApiException {
  const ApiNetworkException(super.message);
}

/// The server responded outside the endpoint's explicitly accepted statuses.
class ApiHttpException extends ApiException {
  const ApiHttpException({
    required this.statusCode,
    required String message,
    this.code,
    this.details,
  }) : super(message);

  final int statusCode;
  final String? code;
  final Map<String, dynamic>? details;
}

/// The server answered successfully but the promised JSON representation was
/// malformed. This is a contract/data error, never a connectivity failure.
class ApiDecodeException extends ApiException {
  const ApiDecodeException(super.message);
}

/// The caller attempted to build a request outside the configured API origin
/// or override a security-owned header.
class ApiRequestConfigurationException extends ApiException {
  const ApiRequestConfigurationException(super.message);
}

/// Authenticated HTTP boundary shared by every live REST repository.
///
/// It owns token injection, a uniform timeout, safe server-error extraction,
/// and an explicit opt-in cache fallback for GET requests that fail before any
/// HTTP response is received. Authenticated responses are never persisted by
/// default. HTTP 4xx/5xx responses always throw and never use a stale value.
class AuthenticatedApiClient {
  AuthenticatedApiClient({
    http.Client? httpClient,
    ApiGetCache? cache,
    ApiIdentityProvider? identityProvider,
    this.timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client(),
       _cache = cache ?? ApiGetCache.shared,
       _identityProvider = identityProvider ?? _firebaseIdentity;

  static final AuthenticatedApiClient shared = AuthenticatedApiClient();

  static const cachedResponseHeader = 'x-footpath-cache';

  final http.Client _httpClient;
  final ApiGetCache _cache;
  final ApiIdentityProvider _identityProvider;
  final Duration timeout;

  Future<http.Response> get(
    String path, {
    Map<String, String> headers = const {},
    Set<int> expectedStatuses = const {200},
    bool cache = false,
    bool cacheFirst = false,
    bool forceRefreshToken = false,
  }) => _request(
    'GET',
    path,
    headers: headers,
    expectedStatuses: expectedStatuses,
    cacheGet: cache,
    cacheFirst: cacheFirst,
    forceRefreshToken: forceRefreshToken,
  );

  Future<http.Response> post(
    String path, {
    Map<String, String> headers = const {},
    Object? body,
    Set<int> expectedStatuses = const {200},
    bool forceRefreshToken = false,
  }) => _request(
    'POST',
    path,
    headers: headers,
    body: body,
    expectedStatuses: expectedStatuses,
    forceRefreshToken: forceRefreshToken,
  );

  Future<http.Response> put(
    String path, {
    Map<String, String> headers = const {},
    Object? body,
    Set<int> expectedStatuses = const {200},
    bool forceRefreshToken = false,
  }) => _request(
    'PUT',
    path,
    headers: headers,
    body: body,
    expectedStatuses: expectedStatuses,
    forceRefreshToken: forceRefreshToken,
  );

  Future<http.Response> patch(
    String path, {
    Map<String, String> headers = const {},
    Object? body,
    Set<int> expectedStatuses = const {200},
    bool forceRefreshToken = false,
  }) => _request(
    'PATCH',
    path,
    headers: headers,
    body: body,
    expectedStatuses: expectedStatuses,
    forceRefreshToken: forceRefreshToken,
  );

  Future<http.Response> delete(
    String path, {
    Map<String, String> headers = const {},
    Object? body,
    Set<int> expectedStatuses = const {204},
    bool forceRefreshToken = false,
  }) => _request(
    'DELETE',
    path,
    headers: headers,
    body: body,
    expectedStatuses: expectedStatuses,
    forceRefreshToken: forceRefreshToken,
  );

  /// Sends an authenticated multipart upload through the same timeout and
  /// error boundary as every other API request. Uploads are writes, so they
  /// are never cached or replayed automatically.
  Future<http.Response> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
    Set<int> expectedStatuses = const {200},
    bool forceRefreshToken = false,
  }) async {
    final uri = _resolveApiUri(path);
    final identity = _identityProvider();
    if (identity == null || identity.uid.isEmpty) {
      throw const ApiAuthenticationException('Not signed in.');
    }

    final String token;
    try {
      final value = await identity.getIdToken(forceRefreshToken);
      if (value == null || value.isEmpty) {
        throw const ApiAuthenticationException('Not signed in.');
      }
      token = value;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        throw const ApiNetworkException(
          'Could not reach the server. Check your connection.',
        );
      }
      throw const ApiAuthenticationException(
        'Could not verify the signed-in account.',
      );
    }

    final request = http.MultipartRequest('POST', uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _httpClient.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
    } on TimeoutException {
      throw const ApiNetworkException('The server took too long to respond.');
    } on SocketException {
      throw const ApiNetworkException(
        'Could not reach the server. Check your connection.',
      );
    } on HandshakeException {
      throw const ApiNetworkException(
        'Could not establish a secure server connection.',
      );
    } on http.ClientException {
      throw const ApiNetworkException(
        'Could not reach the server. Check your connection.',
      );
    }

    if (!expectedStatuses.contains(response.statusCode)) {
      throw ApiHttpException(
        statusCode: response.statusCode,
        message: _serverError(response),
        code: _serverCode(response),
        details: _serverDetails(response),
      );
    }
    return response;
  }

  Future<http.Response> _request(
    String method,
    String path, {
    required Map<String, String> headers,
    Object? body,
    required Set<int> expectedStatuses,
    bool cacheGet = false,
    bool cacheFirst = false,
    bool forceRefreshToken = false,
  }) async {
    final uri = _resolveApiUri(path);
    _rejectSecurityOwnedHeaders(headers);
    final identity = _identityProvider();
    if (identity == null || identity.uid.isEmpty) {
      throw const ApiAuthenticationException('Not signed in.');
    }

    // A short-lived guardian/player unlock is an additional authorization
    // boundary. Do not persist either that token or the protected response.
    final mayCache = cacheGet && !_containsPrivacyUnlock(headers);
    final cacheKey = _cacheKey(uri, headers);

    if (mayCache && cacheFirst) {
      final cached = await _readBestEffort(identity.uid, cacheKey);
      if (cached != null) {
        return http.Response(
          cached.body,
          cached.statusCode,
          headers: {...cached.headers, cachedResponseHeader: 'true'},
        );
      }
    }

    final String token;
    try {
      final value = await identity.getIdToken(forceRefreshToken);
      if (value == null || value.isEmpty) {
        throw const ApiAuthenticationException('Not signed in.');
      }
      token = value;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        return _networkFallback(
          identity.uid,
          cacheKey,
          mayCache,
          const ApiNetworkException(
            'Could not reach the server. Check your connection.',
          ),
        );
      }
      throw const ApiAuthenticationException(
        'Could not verify the signed-in account.',
      );
    }

    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({'Authorization': 'Bearer $token', ...headers});
    if (body != null) {
      request.body = body is String ? body : jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _httpClient.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
    } on TimeoutException {
      return _networkFallback(
        identity.uid,
        cacheKey,
        mayCache,
        const ApiNetworkException('The server took too long to respond.'),
      );
    } on SocketException {
      return _networkFallback(
        identity.uid,
        cacheKey,
        mayCache,
        const ApiNetworkException(
          'Could not reach the server. Check your connection.',
        ),
      );
    } on HandshakeException {
      return _networkFallback(
        identity.uid,
        cacheKey,
        mayCache,
        const ApiNetworkException(
          'Could not establish a secure server connection.',
        ),
      );
    } on http.ClientException {
      return _networkFallback(
        identity.uid,
        cacheKey,
        mayCache,
        const ApiNetworkException(
          'Could not reach the server. Check your connection.',
        ),
      );
    }

    if (!expectedStatuses.contains(response.statusCode)) {
      throw ApiHttpException(
        statusCode: response.statusCode,
        message: _serverError(response),
        code: _serverCode(response),
        details: _serverDetails(response),
      );
    }

    if (mayCache) {
      try {
        jsonDecode(response.body);
      } on FormatException {
        throw const ApiDecodeException(
          'The server returned an invalid JSON response.',
        );
      }
      await _storeBestEffort(identity.uid, cacheKey, response);
    }
    return response;
  }

  Future<http.Response> _networkFallback(
    String ownerUid,
    String cacheKey,
    bool enabled,
    ApiNetworkException error,
  ) async {
    if (enabled) {
      final cached = await _readBestEffort(ownerUid, cacheKey);
      if (cached != null) {
        return http.Response(
          cached.body,
          cached.statusCode,
          headers: {...cached.headers, cachedResponseHeader: 'true'},
        );
      }
    }
    throw error;
  }

  Future<void> _storeBestEffort(
    String ownerUid,
    String cacheKey,
    http.Response response,
  ) async {
    try {
      await _cache.put(
        ownerUid,
        cacheKey,
        CachedApiGet(
          statusCode: response.statusCode,
          body: response.body,
          headers: {
            if (response.headers['content-type'] case final String type)
              'content-type': type,
          },
        ),
      );
    } catch (_) {
      // Cache support is best-effort (notably unavailable on some web builds).
      // A successful server response must still reach its caller.
    }
  }

  Future<CachedApiGet?> _readBestEffort(
    String ownerUid,
    String cacheKey,
  ) async {
    try {
      return await _cache.get(ownerUid, cacheKey);
    } catch (_) {
      return null;
    }
  }

  String _cacheKey(Uri uri, Map<String, String> extraHeaders) {
    final varyingHeaders = extraHeaders.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode({
      'uri': uri.toString(),
      // Authorization is intentionally excluded: owner_uid already isolates
      // accounts. Privacy-unlock and other representation-changing headers are
      // included so a protected response cannot satisfy an unprotected read.
      'headers': {for (final entry in varyingHeaders) entry.key: entry.value},
    });
  }

  bool _containsPrivacyUnlock(Map<String, String> headers) =>
      headers.keys.any((key) => key.toLowerCase() == 'x-player-unlock');

  Uri _resolveApiUri(String path) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final parsed = Uri.tryParse(path);
    if (parsed == null || path.trim().isEmpty) {
      throw const ApiRequestConfigurationException('Invalid API request path.');
    }

    final resolved = parsed.hasScheme
        ? parsed
        : Uri.parse(
            '${ApiConfig.baseUrl}${path.startsWith('/') ? '' : '/'}$path',
          );
    if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty ||
        resolved.origin != base.origin) {
      throw const ApiRequestConfigurationException(
        'Authenticated requests must use the configured API origin.',
      );
    }
    return resolved;
  }

  void _rejectSecurityOwnedHeaders(Map<String, String> headers) {
    if (headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
      throw const ApiRequestConfigurationException(
        'Authorization is managed by the authenticated API client.',
      );
    }
  }

  String _serverError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final candidate = _firstMessage(decoded);
      if (candidate != null) return candidate;
    } on FormatException {
      // Never expose arbitrary HTML/proxy bodies to the UI.
    }
    return 'Request failed (${response.statusCode}).';
  }

  String? _serverCode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic>
          ? decoded['code'] as String?
          : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _serverDetails(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String? _firstMessage(Object? value) {
    if (value is String) return _safeMessage(value);
    if (value is List) {
      for (final item in value) {
        final message = _firstMessage(item);
        if (message != null) return message;
      }
    }
    if (value is Map) {
      if (value['detail'] case final String detail) {
        final message = _safeMessage(detail);
        if (message != null) return message;
      }
      for (final entry in value.entries) {
        if (entry.key == 'detail') continue;
        final message = _firstMessage(entry.value);
        if (message != null) return message;
      }
    }
    return null;
  }

  String? _safeMessage(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    return normalized.length <= 300
        ? normalized
        : '${normalized.substring(0, 297)}...';
  }

  static ApiIdentity? _firebaseIdentity() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return ApiIdentity(uid: user.uid, getIdToken: user.getIdToken);
  }
}
