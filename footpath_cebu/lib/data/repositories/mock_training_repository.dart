import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// In-memory training schedule for UI development without a backend.
///
/// Dates are relative to "now" so both the Upcoming and Past tabs always have
/// content regardless of the calendar date.
class MockTrainingRepository implements TrainingRepository {
  MockTrainingRepository() {
    final now = DateTime.now();
    DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);

    _sessions = [
      TrainingSession(
        id: 't1',
        title: 'Tactical Workshop',
        ageTiers: {AgeTier.pathway},
        date: day(2),
        startTime: '04:30 PM',
        endTime: '06:00 PM',
        location: 'USJ-R Basak Pitch',
        focus: SessionFocus.mental,
        attendeeCount: 22,
      ),
      TrainingSession(
        id: 't2',
        title: 'Technical Drills',
        ageTiers: {AgeTier.development, AgeTier.pathway},
        date: day(4),
        startTime: '06:00 AM',
        endTime: '08:00 AM',
        location: 'Dynamic Herb Sports Complex',
        focus: SessionFocus.technical,
        attendeeCount: 18,
      ),
      TrainingSession(
        id: 't3',
        title: 'Conditioning Test',
        ageTiers: {AgeTier.foundation},
        date: day(6),
        startTime: '05:00 PM',
        endTime: '07:00 PM',
        location: 'Cebu City Sports Center',
        focus: SessionFocus.physical,
        attendeeCount: 9,
      ),
      TrainingSession(
        id: 't4',
        title: 'Set-Piece Review',
        ageTiers: AgeTier.values.toSet(),
        date: day(-3),
        startTime: '04:00 PM',
        endTime: '05:30 PM',
        location: 'USJ-R Basak Pitch',
        focus: SessionFocus.technical,
        attendeeCount: 20,
      ),
      TrainingSession(
        id: 't5',
        title: 'Recovery & Mobility',
        ageTiers: {AgeTier.foundation, AgeTier.development},
        date: day(-8),
        startTime: '07:00 AM',
        endTime: '08:00 AM',
        location: 'Dynamic Herb Sports Complex',
        focus: SessionFocus.physical,
        attendeeCount: 16,
      ),
    ];
  }

  late final List<TrainingSession> _sessions;
  int _nextId = 6;

  @override
  Future<List<TrainingSession>> fetchSessions() async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 500));
    return List.unmodifiable(_sessions);
  }

  @override
  Future<TrainingSession> createSession(TrainingSession draft) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final saved = TrainingSession(
      id: 't${_nextId++}',
      title: draft.title,
      ageTiers: draft.ageTiers,
      date: draft.date,
      startTime: draft.startTime,
      endTime: draft.endTime,
      location: draft.location,
      focus: draft.focus,
      attendeeCount: draft.attendeeCount,
    );
    _sessions.add(saved);
    return saved;
  }
}
