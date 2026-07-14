/// The squad a session is aimed at. Mirrors the age-tier programme names.
enum SquadTier { elite, development, pro }

extension SquadTierLabel on SquadTier {
  String get label {
    switch (this) {
      case SquadTier.elite:
        return 'Elite Squad';
      case SquadTier.development:
        return 'Development Hub';
      case SquadTier.pro:
        return 'Pro Prospects';
    }
  }

  String get wire => name.toUpperCase();

  static SquadTier fromWire(String value) {
    return SquadTier.values.firstWhere(
      (t) => t.wire == value.toUpperCase(),
      orElse: () => SquadTier.development,
    );
  }
}

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
    required this.squad,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.focus,
    this.attendeeCount = 0,
  });

  final String id;
  final String title;
  final SquadTier squad;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;
  final SessionFocus focus;
  final int attendeeCount;

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    return TrainingSession(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      squad: SquadTierLabel.fromWire(json['squad'] as String? ?? ''),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      location: json['location'] as String? ?? '',
      focus: SessionFocusLabel.fromWire(json['focus'] as String? ?? ''),
      attendeeCount: json['attendeeCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'squad': squad.wire,
        'date': date.toIso8601String(),
        'startTime': startTime,
        'endTime': endTime,
        'location': location,
        'focus': focus.wire,
        'attendeeCount': attendeeCount,
      };
}
