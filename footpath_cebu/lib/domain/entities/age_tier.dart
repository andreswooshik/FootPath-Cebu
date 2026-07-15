/// The academy's three age tiers — the single source of truth for tiering,
/// shared by [Player] (which tier a player belongs to) and [TrainingSession]
/// (which tier a session is run for).
///
/// Adding a fourth tier is one case here plus the `switch` arms below; every
/// tier-aware widget is driven by [AgeTier.values], so no UI needs new code.
enum AgeTier { foundation, development, pathway }

extension AgeTierInfo on AgeTier {
  /// Programme name shown to coaches, e.g. "Foundation".
  String get label {
    switch (this) {
      case AgeTier.foundation:
        return 'Foundation';
      case AgeTier.development:
        return 'Development';
      case AgeTier.pathway:
        return 'Pathway';
    }
  }

  /// Inclusive age bounds for the tier.
  ({int min, int max}) get ageRange {
    switch (this) {
      case AgeTier.foundation:
        return (min: 10, max: 12);
      case AgeTier.development:
        return (min: 13, max: 15);
      case AgeTier.pathway:
        return (min: 16, max: 18);
    }
  }

  /// Age bounds as a label, e.g. "Ages 10–12".
  String get ageLabel => 'Ages ${ageRange.min}–${ageRange.max}';

  /// Wire value used by the backend (FOUNDATION / DEVELOPMENT / PATHWAY).
  String get wire => name.toUpperCase();

  /// True when [age] falls inside this tier's bounds.
  bool includesAge(int age) => age >= ageRange.min && age <= ageRange.max;

  static AgeTier fromWire(String value) {
    return AgeTier.values.firstWhere(
      (t) => t.wire == value.toUpperCase(),
      orElse: () => AgeTier.development,
    );
  }

  /// The tier [age] falls into, or null if it sits outside every tier.
  ///
  /// This is the *default* at registration only — a player's tier is stored,
  /// not derived, so a coach can hold someone in a lower tier and nobody's
  /// tier shifts on their birthday mid-season.
  static AgeTier? forAge(int age) {
    for (final tier in AgeTier.values) {
      if (tier.includesAge(age)) return tier;
    }
    return null;
  }
}
