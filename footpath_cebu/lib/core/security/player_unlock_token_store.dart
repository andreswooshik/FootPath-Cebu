/// In-memory store for short-lived server-issued player unlock grants.
///
/// Tokens are never persisted and are cleared when the authenticated session
/// ends. Repositories receive this store through dependency injection.
class PlayerUnlockTokenStore {
  final Map<String, String> _tokens = {};

  String? tokenFor(String playerId) => _tokens[playerId];

  void put(String playerId, String token) => _tokens[playerId] = token;

  void clear() => _tokens.clear();
}
