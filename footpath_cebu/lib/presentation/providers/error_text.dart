import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// Maps an [AsyncValue.error] to the message the user should see.
///
/// Domain repository exceptions carry a human-readable [message] written for
/// the UI; anything else (a bug, a decode failure) falls back to the
/// screen-specific [fallback] so raw exception text never reaches the user.
String friendlyErrorMessage(Object? error, String fallback) => switch (error) {
      PlayerRepositoryException e => e.message,
      AttendanceRepositoryException e => e.message,
      TrainingRepositoryException e => e.message,
      AuthException e => e.message,
      _ => fallback,
    };
