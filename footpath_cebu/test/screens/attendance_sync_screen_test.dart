import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/domain/repositories/attendance_sync_repository.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/attendance_sync_screen.dart';

class _SyncRepository implements AttendanceSyncRepository {
  _SyncRepository(this.entry);
  final AttendanceSyncEntry entry;
  List<Attendance>? corrected;
  int syncCalls = 0;
  @override
  Future<List<AttendanceSyncEntry>> fetchEntries() async => [entry];
  @override
  Stream<List<AttendanceSyncEntry>> watchEntries() => Stream.value([entry]);
  @override
  Future<void> syncNow() async {
    syncCalls++;
  }

  @override
  Future<void> saveCorrection(
    AttendanceSyncEntry entry,
    List<Attendance> records,
  ) async {
    corrected = records;
  }
}

AttendanceSyncEntry _entry(AttendanceDeliveryStatus status) =>
    AttendanceSyncEntry(
      sessionId: 'deleted-session',
      recoveryKey: 'coach:1',
      status: status,
      error: status == AttendanceDeliveryStatus.needsCorrection
          ? 'Session is closed.'
          : null,
      records: [
        Attendance(
          playerId: 'p1',
          sessionId: 'deleted-session',
          sessionName: 'Retained training',
          status: AttendanceStatus.present,
          updatedAt: DateTime(2026, 9, 1),
          effort: 75,
          performanceScore: 8,
          note: 'Keep this observation.',
        ),
      ],
    );

void main() {
  Future<_SyncRepository> pump(
    WidgetTester tester, {
    AttendanceDeliveryStatus status = AttendanceDeliveryStatus.needsCorrection,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _SyncRepository(_entry(status));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceSyncRepositoryProvider.overrideWithValue(repository),
          squadProvider.overrideWith((ref) async => throw Exception('offline')),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const AttendanceSyncScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets(
    'rejected attendance shows reason and does not offer automatic retry',
    (tester) async {
      await pump(tester);
      expect(find.text('Needs correction'), findsOneWidget);
      expect(find.text('Session is closed.'), findsOneWidget);
      expect(find.text('Sync now'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('waiting attendance offers manual sync', (tester) async {
    final repository = await pump(
      tester,
      status: AttendanceDeliveryStatus.waitingToSync,
    );
    expect(find.text('Waiting to sync'), findsOneWidget);
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();
    expect(repository.syncCalls, 1);
  });

  testWidgets(
    'retained marks remain editable without a live session or roster',
    (tester) async {
      final repository = await pump(tester);
      await tester.ensureVisible(find.text('Review saved marks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review saved marks'));
      await tester.pumpAndSettle();
      expect(find.text('Player p1'), findsOneWidget);
      expect(find.text('Keep this observation.'), findsOneWidget);
      final note = find.widgetWithText(TextFormField, 'Note');
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      await tester.enterText(note, 'Corrected observation.');
      await tester.tap(find.text('Save corrections'));
      await tester.pumpAndSettle();
      expect(repository.corrected!.single.note, 'Corrected observation.');
      expect(repository.corrected!.single.effort, 75);
      expect(repository.corrected!.single.performanceScore, 8);
      expect(find.text('Attendance sync'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid participation values block correction submission', (
    tester,
  ) async {
    final repository = await pump(tester);
    await tester.ensureVisible(find.text('Review saved marks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review saved marks'));
    await tester.pumpAndSettle();
    final effort = find.widgetWithText(
      TextFormField,
      'Effort (0–100, optional)',
    );
    await tester.ensureVisible(effort);
    await tester.pumpAndSettle();
    await tester.enterText(effort, '101');
    await tester.tap(find.text('Save corrections'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 0 to 100.'), findsOneWidget);
    expect(repository.corrected, isNull);
  });

  testWidgets('leaving unsaved edits preserves the retained copy', (
    tester,
  ) async {
    final repository = await pump(tester);
    await tester.ensureVisible(find.text('Review saved marks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review saved marks'));
    await tester.pumpAndSettle();
    final note = find.widgetWithText(TextFormField, 'Note');
    await tester.ensureVisible(note);
    await tester.pumpAndSettle();
    await tester.enterText(note, 'Unsaved edit');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved corrections?'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(repository.corrected, isNull);
    expect(repository.entry.records.single.note, 'Keep this observation.');
  });
}
