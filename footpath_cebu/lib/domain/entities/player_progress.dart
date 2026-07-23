import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// One player's attendance/effort aggregates — a row in the coach's Progress
/// tab. Immutable Model — no UI, no I/O.
class PlayerProgress {
  const PlayerProgress({
    required this.id,
    required this.name,
    this.position,
    required this.ageTier,
    required this.present,
    required this.absent,
    required this.excused,
    this.avgEffort,
  });

  final String id;
  final String name;
  final PlayerPosition? position;
  final AgeTier ageTier;

  /// Attendance counts across every session with a recorded status.
  final int present;
  final int absent;
  final int excused;

  /// Mean of the coach's per-session effort marks (0–100); null when no
  /// session has one yet.
  final int? avgEffort;

  int get totalRecorded => present + absent + excused;

  /// Share of recorded sessions attended, 0–1; null before any roll call so
  /// a new player shows "no data" rather than a damning 0%.
  double? get attendanceRate =>
      totalRecorded == 0 ? null : present / totalRecorded;

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    return PlayerProgress(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      position: PlayerPositionInfo.fromWire(json['position'] as String?),
      ageTier: AgeTierInfo.fromWire(json['ageTier'] as String? ?? ''),
      present: json['present'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      excused: json['excused'] as int? ?? 0,
      avgEffort: json['avgEffort'] as int?,
    );
  }
}
