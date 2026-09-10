import 'package:footpath_cebu/domain/entities/dispute.dart';

abstract final class DisputeDto {
  static Dispute fromJson(Map<String, dynamic> json) => Dispute(
    id: json['id'].toString(),
    category: categoryFromWire(json['category'] as String),
    status: statusFromWire(json['status'] as String),
    summary: json['summary'] as String,
    detail: _blankAsNull(json['detail'] as String?),
    raisedByName: json['raisedByName'] as String?,
    subjectPlayerId: json['subjectPlayerId']?.toString(),
    subjectPlayerName: json['subjectPlayerName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    responses: (json['responses'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(responseFromJson)
        .toList(growable: false),
  );

  static DisputeResponse responseFromJson(Map<String, dynamic> json) {
    final statusChange = json['statusChangeTo'] as String?;
    return DisputeResponse(
      id: json['id'].toString(),
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorName: json['authorName'] as String?,
      authorRole: json['authorRole'] as String?,
      statusChangeTo: statusChange == null
          ? null
          : statusFromWire(statusChange),
    );
  }

  static String categoryToWire(DisputeCategory category) =>
      category.name.toUpperCase();

  static DisputeCategory categoryFromWire(String value) =>
      DisputeCategory.values.firstWhere(
        (category) => categoryToWire(category) == value.toUpperCase(),
        orElse: () => DisputeCategory.other,
      );

  static String statusToWire(DisputeStatus status) => switch (status) {
    DisputeStatus.open => 'OPEN',
    DisputeStatus.underReview => 'UNDER_REVIEW',
    DisputeStatus.resolved => 'RESOLVED',
    DisputeStatus.dismissed => 'DISMISSED',
  };

  static DisputeStatus statusFromWire(String value) =>
      DisputeStatus.values.firstWhere(
        (status) => statusToWire(status) == value.toUpperCase(),
        orElse: () => DisputeStatus.open,
      );

  static String? _blankAsNull(String? value) =>
      value == null || value.isEmpty ? null : value;
}
