import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/player_security_providers.dart';
import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_sync_service.dart';
import 'package:footpath_cebu/data/local/attendance_write_queue.dart';
import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/local_attendance_sync_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/offline_first_attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_sync_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/log_session_attendance.dart';

final attendanceOutboxProvider = Provider<AttendanceOutbox>((ref) {
  final outbox = AttendanceOutbox();
  ref.onDispose(outbox.close);
  return outbox;
});

final attendanceWriteQueueProvider = Provider<AttendanceWriteQueue>(
  (ref) => AttendanceWriteQueue(),
);

final attendanceSyncRepositoryProvider = Provider<AttendanceSyncRepository>((
  ref,
) {
  if (useMockData || kIsWeb) return OnlineAttendanceSyncRepository();
  return LocalAttendanceSyncRepository(
    outbox: ref.watch(attendanceOutboxProvider),
    writeQueue: ref.watch(attendanceWriteQueueProvider),
    ownerUid: () => FirebaseAuth.instance.currentUser?.uid,
    requestSync: () async {
      await ref.read(attendanceSyncServiceProvider)?.drain();
    },
  );
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => useMockData
      ? MockAttendanceRepository()
      : kIsWeb
      ? ApiAttendanceRepository(
          unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
        )
      : OfflineFirstAttendanceRepository(
          inner: ApiAttendanceRepository(
            unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
          ),
          outbox: ref.watch(attendanceOutboxProvider),
          writeQueue: ref.watch(attendanceWriteQueueProvider),
          requestSync: () {
            if (ref.mounted) {
              unawaited(ref.read(attendanceSyncServiceProvider)?.drain());
            }
          },
          ownerUid: () => FirebaseAuth.instance.currentUser?.uid,
        ),
);

final attendanceSyncServiceProvider = Provider<AttendanceSyncService?>((ref) {
  if (useMockData || kIsWeb) return null;
  final service = AttendanceSyncService(
    outbox: ref.watch(attendanceOutboxProvider),
    writeQueue: ref.watch(attendanceWriteQueueProvider),
    inner: ApiAttendanceRepository(
      unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
    ),
    ownerUid: () => FirebaseAuth.instance.currentUser?.uid,
  );
  ref.onDispose(service.dispose);
  return service;
});

final getPlayerAttendanceProvider = Provider<GetPlayerAttendance>(
  (ref) => GetPlayerAttendance(ref.watch(attendanceRepositoryProvider)),
);

final getSessionAttendanceProvider = Provider<GetSessionAttendance>(
  (ref) => GetSessionAttendance(ref.watch(attendanceRepositoryProvider)),
);

final logSessionAttendanceProvider = Provider<LogSessionAttendance>(
  (ref) => LogSessionAttendance(ref.watch(attendanceRepositoryProvider)),
);
