import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/presentation/providers/attendance_sync_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

/// Edits the retained snapshot without requiring a live roster or session.
/// The server still decides whether the corrected attendance is permitted.
class AttendanceRecoveryScreen extends ConsumerStatefulWidget {
  const AttendanceRecoveryScreen({super.key, required this.entry});
  final AttendanceSyncEntry entry;
  @override
  ConsumerState<AttendanceRecoveryScreen> createState() =>
      _AttendanceRecoveryScreenState();
}

class _AttendanceRecoveryScreenState
    extends ConsumerState<AttendanceRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  late final List<_RecordDraft> _drafts = widget.entry.records
      .map(_RecordDraft.new)
      .toList();
  bool _dirty = false;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved corrections?'),
        content: const Text(
          'The previously saved attendance will stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (!mounted || leave != true) return;
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final records = _drafts.map((draft) => draft.toRecord()).toList();
    final ok = await ref
        .read(attendanceSyncControllerProvider.notifier)
        .saveCorrection(widget.entry, records);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              ref.read(attendanceSyncControllerProvider).error,
              'Could not save corrections. Your retained marks are unchanged.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Corrections saved. Check Attendance sync for delivery status.',
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(attendanceSyncControllerProvider).isLoading;
    final players = ref.watch(squadProvider).asData?.value ?? [];
    final names = {for (final player in players) player.id: player.name};
    return PopScope(
      canPop: !_dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Review saved marks')),
        body: Form(
          key: _form,
          onChanged: () {
            if (!_dirty) setState(() => _dirty = true);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.entry.sessionName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.entry.error != null) Text(widget.entry.error!),
              const Text(
                'These marks are retained on this device. Remove a record only if that player should not be included in this session.',
              ),
              for (final draft in _drafts)
                Card(
                  key: ObjectKey(draft),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          names[draft.original.playerId] ??
                              'Player ${draft.original.playerId}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        DropdownButtonFormField<AttendanceStatus>(
                          initialValue: draft.status,
                          decoration: const InputDecoration(
                            labelText: 'Attendance',
                          ),
                          items: [
                            for (final status in AttendanceStatus.values)
                              DropdownMenuItem(
                                value: status,
                                child: Text(status.label),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (status) {
                                  if (status != null) {
                                    setState(() {
                                      draft.status = status;
                                      _dirty = true;
                                    });
                                  }
                                },
                        ),
                        if (draft.status == AttendanceStatus.present) ...[
                          TextFormField(
                            controller: draft.effort,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: 'Effort (0–100, optional)',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                _numberError(value, 100, integer: true),
                          ),
                          TextFormField(
                            controller: draft.score,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: 'Performance (0–10, optional)',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (value) => _numberError(value, 10),
                          ),
                        ],
                        TextFormField(
                          controller: draft.note,
                          enabled: !busy,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Note'),
                        ),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final remove = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text(
                                        'Remove this attendance record?',
                                      ),
                                      content: const Text(
                                        'The record is removed from your correction draft. The retained copy stays unchanged until you save corrections.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Keep record'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (mounted && remove == true) {
                                    setState(() {
                                      _drafts.remove(draft);
                                      _dirty = true;
                                    });
                                    // Dispose after its text fields have left the widget tree.
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => draft.dispose(),
                                        );
                                  }
                                },
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Remove record'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_drafts.isEmpty)
                const Text(
                  'No records remain. Saving an empty correction will clear the session’s attendance if the server accepts it.',
                ),
              const SizedBox(height: 80),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: busy ? null : _save,
              child: Text(busy ? 'Saving…' : 'Save corrections'),
            ),
          ),
        ),
      ),
    );
  }

  String? _numberError(String? text, int max, {bool integer = false}) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return null;
    final number = integer ? int.tryParse(value) : double.tryParse(value);
    if (number == null || !number.isFinite || number < 0 || number > max) {
      return 'Enter ${integer ? 'a whole number' : 'a number'} from 0 to $max.';
    }
    return null;
  }
}

class _RecordDraft {
  _RecordDraft(this.original)
    : status = original.status,
      effort = TextEditingController(text: original.effort?.toString() ?? ''),
      score = TextEditingController(
        text: original.performanceScore?.toString() ?? '',
      ),
      note = TextEditingController(text: original.note ?? '');
  final Attendance original;
  AttendanceStatus status;
  final TextEditingController effort;
  final TextEditingController score;
  final TextEditingController note;

  Attendance toRecord() => Attendance(
    playerId: original.playerId,
    sessionId: original.sessionId,
    sessionName: original.sessionName,
    status: status,
    updatedAt: DateTime.now(),
    effort: status == AttendanceStatus.present
        ? int.tryParse(effort.text.trim())
        : null,
    performanceScore: status == AttendanceStatus.present
        ? double.tryParse(score.text.trim())
        : null,
    note: note.text.trim(),
  );
  void dispose() {
    effort.dispose();
    score.dispose();
    note.dispose();
  }
}
