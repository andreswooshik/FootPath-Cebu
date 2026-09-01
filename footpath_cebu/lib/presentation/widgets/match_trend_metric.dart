import 'package:footpath_cebu/domain/entities/match_performance.dart';

enum MatchTrendMetric { rating, passing, goals, assists, tackles }

extension MatchTrendMetricInfo on MatchTrendMetric {
  String get label => switch (this) {
    MatchTrendMetric.rating => 'Match Rating',
    MatchTrendMetric.passing => 'Passing',
    MatchTrendMetric.goals => 'Goals',
    MatchTrendMetric.assists => 'Assists',
    MatchTrendMetric.tackles => 'Tackles',
  };

  String get unit => switch (this) {
    MatchTrendMetric.passing => '%',
    _ => '',
  };

  double? valueFor(MatchPerformance row) => switch (this) {
    MatchTrendMetric.rating => row.coachRating,
    MatchTrendMetric.passing => row.passCompletionRate,
    MatchTrendMetric.goals => row.goals.toDouble(),
    MatchTrendMetric.assists => row.assists.toDouble(),
    MatchTrendMetric.tackles => row.tackles.toDouble(),
  };

  double maxValueFor(Iterable<MatchPerformance> rows) {
    if (this == MatchTrendMetric.rating) return 10;
    if (this == MatchTrendMetric.passing) return 100;
    final values = rows.map(valueFor).whereType<double>();
    final largest = values.fold<double>(
      1,
      (max, value) => value > max ? value : max,
    );
    return largest * 1.2;
  }
}
