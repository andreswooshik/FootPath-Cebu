/// The line a position belongs to. Positions are grouped by this in the
/// picker, because that's how a coach reads a squad — keeper, back line,
/// midfield, front line — not as one flat list of ten.
enum PositionGroup { goalkeeper, defence, midfield, attack }

extension PositionGroupLabel on PositionGroup {
  String get label {
    switch (this) {
      case PositionGroup.goalkeeper:
        return 'Goalkeeper';
      case PositionGroup.defence:
        return 'Defence';
      case PositionGroup.midfield:
        return 'Midfield';
      case PositionGroup.attack:
        return 'Attack';
    }
  }
}

/// A player's football position.
///
/// Deliberately has no "unassigned" member: a player without a position is
/// modelled as a null [Player.position], so an unassigned player is
/// unmistakable rather than hiding behind a placeholder value. Positions are
/// set by the coach after evaluation, never at registration.
enum PlayerPosition {
  goalkeeper,
  centerBack,
  leftBack,
  rightBack,
  defensiveMidfielder,
  centralMidfielder,
  attackingMidfielder,
  leftWinger,
  rightWinger,
  striker,
}

extension PlayerPositionInfo on PlayerPosition {
  /// Short code shown on the FUT card and roster, e.g. "ST".
  String get code {
    switch (this) {
      case PlayerPosition.goalkeeper:
        return 'GK';
      case PlayerPosition.centerBack:
        return 'CB';
      case PlayerPosition.leftBack:
        return 'LB';
      case PlayerPosition.rightBack:
        return 'RB';
      case PlayerPosition.defensiveMidfielder:
        return 'CDM';
      case PlayerPosition.centralMidfielder:
        return 'CM';
      case PlayerPosition.attackingMidfielder:
        return 'CAM';
      case PlayerPosition.leftWinger:
        return 'LW';
      case PlayerPosition.rightWinger:
        return 'RW';
      case PlayerPosition.striker:
        return 'ST';
    }
  }

  /// Full name shown in the picker, e.g. "Striker".
  String get label {
    switch (this) {
      case PlayerPosition.goalkeeper:
        return 'Goalkeeper';
      case PlayerPosition.centerBack:
        return 'Center Back';
      case PlayerPosition.leftBack:
        return 'Left Back';
      case PlayerPosition.rightBack:
        return 'Right Back';
      case PlayerPosition.defensiveMidfielder:
        return 'Defensive Midfielder';
      case PlayerPosition.centralMidfielder:
        return 'Central Midfielder';
      case PlayerPosition.attackingMidfielder:
        return 'Attacking Midfielder';
      case PlayerPosition.leftWinger:
        return 'Left Winger';
      case PlayerPosition.rightWinger:
        return 'Right Winger';
      case PlayerPosition.striker:
        return 'Striker';
    }
  }

  PositionGroup get group {
    switch (this) {
      case PlayerPosition.goalkeeper:
        return PositionGroup.goalkeeper;
      case PlayerPosition.centerBack:
      case PlayerPosition.leftBack:
      case PlayerPosition.rightBack:
        return PositionGroup.defence;
      case PlayerPosition.defensiveMidfielder:
      case PlayerPosition.centralMidfielder:
      case PlayerPosition.attackingMidfielder:
        return PositionGroup.midfield;
      case PlayerPosition.leftWinger:
      case PlayerPosition.rightWinger:
      case PlayerPosition.striker:
        return PositionGroup.attack;
    }
  }

  /// "Striker (ST)" — for confirmation copy and the profile section.
  String get labelWithCode => '$label ($code)';

  /// Wire value used by the backend. The short code, not the enum name, so the
  /// API stays readable and matches what was stored before this was an enum.
  String get wire => code;

  /// The positions in [group], in declaration order.
  static List<PlayerPosition> inGroup(PositionGroup group) =>
      PlayerPosition.values.where((p) => p.group == group).toList(
            growable: false,
          );

  /// Reads a wire value, or null when the player has no position yet.
  ///
  /// Returns null rather than a fallback for an unknown value: guessing a
  /// position the coach never chose would be worse than showing none.
  static PlayerPosition? fromWire(String? value) {
    if (value == null || value.isEmpty) return null;
    final upper = value.toUpperCase();
    for (final position in PlayerPosition.values) {
      if (position.wire == upper) return position;
    }
    return null;
  }
}
