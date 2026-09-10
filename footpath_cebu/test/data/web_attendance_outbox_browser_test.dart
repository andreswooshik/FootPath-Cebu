@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/web_attendance_outbox.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:idb_shim/idb_browser.dart';

void main() {
  test('browser IndexedDB retains an attendance batch after reopen', () async {
    final databaseName =
        'footpath-browser-test-${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => idbFactoryBrowser.deleteDatabase(databaseName));
    final first = WebAttendanceOutbox(
      idbFactoryBrowser,
      databaseName: databaseName,
    );
    await first.enqueue(
      'coach-web',
      'session-1',
      [
        Attendance(
          playerId: 'player-1',
          sessionId: 'session-1',
          status: AttendanceStatus.present,
          updatedAt: DateTime(2026, 9, 11),
        ),
      ],
      requestId: 'browser-request-0001',
      expectedRevision: 3,
    );
    await first.close();

    final reopened = WebAttendanceOutbox(
      idbFactoryBrowser,
      databaseName: databaseName,
    );
    final batch = (await reopened.pendingBatches('coach-web')).single;
    expect(batch.requestId, 'browser-request-0001');
    expect(batch.expectedRevision, 3);
    expect(batch.records.single.playerId, 'player-1');
    await reopened.close();
  });
}
