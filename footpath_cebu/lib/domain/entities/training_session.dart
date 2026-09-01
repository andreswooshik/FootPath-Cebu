import 'package:footpath_cebu/domain/entities/age_tier.dart';

/// The primary emphasis of a training session.
enum SessionFocus { technical, physical, mental }

enum TrainingSessionStatus { scheduled, completed, cancelled }

extension TrainingSessionStatusInfo on TrainingSessionStatus {
  String get label => switch (this) {
    TrainingSessionStatus.scheduled => 'Scheduled',
    TrainingSessionStatus.completed => 'Completed',
    TrainingSessionStatus.cancelled => 'Cancelled',
  };

  static TrainingSessionStatus fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'COMPLETED' => TrainingSessionStatus.completed,
        'CANCELLED' => TrainingSessionStatus.cancelled,
        _ => TrainingSessionStatus.scheduled,
      };
}

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
/// the scheduling form and combined with [date] when calendar state is derived.
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
    this.status = TrainingSessionStatus.scheduled,
    this.cancellationReason = '',
    this.conflictingTournamentId,
    this.conflictingFixtureId,
    this.cancelledAt,
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
  final TrainingSessionStatus status;
  final String cancellationReason;
  final String? conflictingTournamentId;
  final String? conflictingFixtureId;
  final DateTime? cancelledAt;

  bool get isCancelled => status == TrainingSessionStatus.cancelled;

  /// Local end date/time derived from the API's date-only + 12-hour clock
  /// representation. Invalid legacy values stay null and fall back to
  /// date-only classification in [hasEndedAt].
  DateTime? get scheduledEndAt {
    final match = RegExp(
      r'^(0?[1-9]|1[0-2]):([0-5][0-9])\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(endTime.trim());
    if (match == null) return null;

    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!.toUpperCase();
    final hour24 = hour % 12 + (period == 'PM' ? 12 : 0);
    return DateTime(date.year, date.month, date.day, hour24, minute);
  }

  /// Whether this session belongs in Past Sessions at [now]. Completed and
  /// cancelled records are historical immediately; scheduled sessions move
  /// after their actual end time instead of remaining Upcoming all day.
  bool hasEndedAt(DateTime now) {
    if (status != TrainingSessionStatus.scheduled) return true;
    final end = scheduledEndAt;
    if (end != null) return !now.isBefore(end);

    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(date.year, date.month, date.day);
    return sessionDay.isBefore(today);
  }

  /// True only on the calendar day the session takes place.
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// [ageTiers] in canonical tier order, so display never depends on the order
  /// the coach happened to tap the chips in.
  List<AgeTier> get orderedTiers =>
      AgeTier.values.where(ageTiers.contains).toList(growable: false);

  /// True when the session targets every tier the academy runs.
  bool get isAllTiers => ageTiers.length == AgeTier.values.length;

  /// True while the coach may still log this session's attendance: from the
  /// session day itself through two days after. You record who showed up close
  /// to when it happened — never before the session, and not indefinitely late
  /// (a two-day grace covers a coach who couldn't finish the roll call on the
  /// day, then the window closes).
  bool get isAttendanceOpen {
    if (isCancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final daysSince = today.difference(day).inDays;
    return daysSince >= 0 && daysSince <= 2;
  }

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
      status: TrainingSessionStatusInfo.fromWire(json['status'] as String?),
      cancellationReason: json['cancellationReason'] as String? ?? '',
      conflictingTournamentId: json['conflictingTournamentId']?.toString(),
      conflictingFixtureId: json['conflictingFixtureId']?.toString(),
      cancelledAt: json['cancelledAt'] == null
          ? null
          : DateTime.parse(json['cancelledAt'] as String),
    );
  }

  /// Reads the `ageTiers` wire list. Falls back to every tier when the field is
  /// missing or unreadable — a tier-less session can't be rendered or attended,
  /// and a pill reading "All Tiers" is visibly wrong to the coach who created
  /// it, where an empty session would just look broken.
  static Set<AgeTier> _tiersFromJson(dynamic raw) {
    if (raw is! List || raw.isEmpty) return AgeTier.values.toSet();
    return raw.map((v) => AgeTierInfo.fromWire(v.toString())).toSet();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'ageTiers': orderedTiers.map((t) => t.wire).toList(growable: false),
    // Date-only wire format (YYYY-MM-DD): the backend `date` is a Django
    // DateField and rejects a full ISO timestamp. Mirrors InjuryRecord.
    'date': date.toIso8601String().split('T').first,
    'startTime': startTime,
    'endTime': endTime,
    'location': location,
    'focus': focus.wire,
    'attendeeCount': attendeeCount,
  };
}
