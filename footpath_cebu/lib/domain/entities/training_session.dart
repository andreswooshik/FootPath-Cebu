import 'package:footpath_cebu/domain/entities/age_tier.dart';

/// The primary emphasis of a training session.
enum SessionFocus { technical, physical, mental }

extension SessionFocusLabel on SessionFocus {
  String get label {
    switch (this) {
      case SessionFocus.technical:
        return 'Technical';
      case SessionFocus.physical:
        return 'Physical';
      case SessionFocus.mental:
        return 'Mental';
    }
  }

  String get wire => name.toUpperCase();

  static SessionFocus fromWire(String value) {
    return SessionFocus.values.firstWhere(
      (f) => f.wire == value.toUpperCase(),
      orElse: () => SessionFocus.technical,
    );
  }
}

/// A scheduled training session on the coach's calendar. Immutable Model —
/// no UI, no I/O. Times are stored as display strings (e.g. "04:30 PM") set by
/// the scheduling form; [date] carries the calendar day used to split the
/// schedule into Upcoming and Past.
class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.title,
    required this.ageTiers,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.focus,
    this.attendeeCount = 0,
  });

  final String id;
  final String title;

  /// The tiers this session is run for — one, some, or all of them. Only
  /// players in these tiers are eligible for its attendance. A session with no
  /// tiers targets nobody, so the scheduling form requires at least one.
  ///
  /// Stored as the explicit set the coach picked rather than an "all" flag: if
  /// a fourth tier is added later, existing sessions keep targeting exactly the
  /// tiers they were created for instead of silently absorbing the new one.
  final Set<AgeTier> ageTiers;

  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;
  final SessionFocus focus;
  final int attendeeCount;

  /// [ageTiers] in canonical tier order, so display never depends on the order
  /// the coach happened to tap the chips in.
  List<AgeTier> get orderedTiers =>
      AgeTier.values.where(ageTiers.contains).toList(growable: false);

  /// True when the session targets every tier the academy runs.
  bool get isAllTiers => ageTiers.length == AgeTier.values.length;

  /// True when a player in [tier] is eligible for this session's attendance.
  bool includesTier(AgeTier tier) => ageTiers.contains(tier);

  /// Names the session's tiers: "All Tiers" when it targets everything,
  /// otherwise the tier names joined — "Foundation · Development".
  String get tiersLabel {
    if (ageTiers.isEmpty) return 'No tiers';
    if (isAllTiers) return 'All Tiers';
    return orderedTiers.map((t) => t.label).join(' · ');
  }

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    return TrainingSession(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      ageTiers: _tiersFromJson(json['ageTiers']),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      location: json['location'] as String? ?? '',
      focus: SessionFocusLabel.fromWire(json['focus'] as String? ?? ''),
      attendeeCount: json['attendeeCount'] as int? ?? 0,
    );
  }

  /// Reads the `ageTiers` wire list. Falls back to every tier when the field is
  /// missing or unreadable — a tier-less session can't be rendered or attended,
  /// and a pill reading "All Tiers" is visibly wrong to the coach who created
  /// it, where an empty session would just look broken.
  static Set<AgeTier> _tiersFromJson(dynamic raw) {
    if (raw is! List || raw.isEmpty) return AgeTier.values.toSet();
    return raw
        .map((v) => AgeTierInfo.fromWire(v.toString()))
        .toSet();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'ageTiers': orderedTiers.map((t) => t.wire).toList(growable: false),
        'date': date.toIso8601String(),
        'startTime': startTime,
        'endTime': endTime,
        'location': location,
        'focus': focus.wire,
        'attendeeCount': attendeeCount,
      };
}
