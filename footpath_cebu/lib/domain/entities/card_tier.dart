import 'package:footpath_cebu/domain/entities/player.dart';

/// A FUT-style collectible-card tier, earned from a player's overall rating.
///
/// Pure domain logic — no Flutter imports — so it can be unit-tested and
/// reused by any widget. The colour is exposed as an ARGB int to keep this
/// layer UI-framework-agnostic; the presentation layer wraps it in a `Color`.
enum CardTier {
  bronze(label: 'Bronze', argb: 0xFFCD7F32, minOverall: 0),
  silver(label: 'Silver', argb: 0xFFBFC7CF, minOverall: 65),
  gold(label: 'Gold', argb: 0xFFE7C86A, minOverall: 80);

  const CardTier({
    required this.label,
    required this.argb,
    required this.minOverall,
  });

  final String label;
  final int argb;

  /// Inclusive lower bound of the overall rating that earns this tier.
  final int minOverall;

  /// The highest tier whose [minOverall] the rating reaches.
  static CardTier forOverall(int overall) {
    if (overall >= gold.minOverall) return gold;
    if (overall >= silver.minOverall) return silver;
    return bronze;
  }

  static CardTier forPlayer(Player player) => forOverall(player.overall);

  /// The tier above this one, or null when already Gold.
  CardTier? get nextTier => switch (this) {
    bronze => silver,
    silver => gold,
    gold => null,
  };
}
