import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

/// Coach Portal — the Schedule New Session form.
///
/// Collects the session details and hands a draft [TrainingSession] to
/// [ScheduleSessionController]. On success it pops back to the schedule,
/// which refreshes by itself (the controller invalidates the schedule
/// provider).
class ScheduleSessionScreen extends ConsumerStatefulWidget {
  const ScheduleSessionScreen({super.key});

  @override
  ConsumerState<ScheduleSessionScreen> createState() =>
      _ScheduleSessionScreenState();
}

class _ScheduleSessionScreenState extends ConsumerState<ScheduleSessionScreen> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();

  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  SessionFocus _focus = SessionFocus.technical;

  /// Tiers the session is for. Starts empty so the coach must choose — a
  /// pre-selected tier is how sessions end up silently assigned to the wrong
  /// players.
  final Set<AgeTier> _tiers = {};

  bool get _allTiersSelected => _tiers.length == AgeTier.values.length;

  void _toggleTier(AgeTier tier) {
    setState(() {
      if (!_tiers.remove(tier)) _tiers.add(tier);
    });
  }

  void _toggleAllTiers() {
    setState(() {
      if (_allTiersSelected) {
        _tiers.clear();
      } else {
        _tiers.addAll(AgeTier.values);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => isStart ? _startTime = picked : _endTime = picked);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    if (title.isEmpty ||
        location.isEmpty ||
        _date == null ||
        _startTime == null ||
        _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all the fields.')),
      );
      return;
    }
    if (_tiers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick at least one age tier for this session.'),
        ),
      );
      return;
    }

    final draft = TrainingSession(
      id: '',
      title: title,
      ageTiers: Set.of(_tiers),
      date: _date!,
      startTime: _startTime!.format(context),
      endTime: _endTime!.format(context),
      location: location,
      focus: _focus,
    );

    final ok = await ref
        .read(scheduleSessionControllerProvider.notifier)
        .submit(draft);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$title" scheduled.')));
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(scheduleSessionControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Could not schedule the session. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(scheduleSessionControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, size: 20),
            SizedBox(width: 8),
            Text('FootPath Cebu'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Schedule New Session',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Plan a new training session for your squad.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),

          const _FieldLabel('Session Title'),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration(
              hint: 'e.g. Tactical Workshop',
              suffix: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 18),

          const _FieldLabel('Date'),
          _PickerField(
            text: _date == null ? 'Select a date' : _formatDate(_date!),
            placeholder: _date == null,
            icon: Icons.calendar_today_outlined,
            onTap: _pickDate,
          ),
          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Start Time'),
                    _PickerField(
                      text: _startTime?.format(context) ?? 'Start',
                      placeholder: _startTime == null,
                      icon: Icons.schedule,
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('End Time'),
                    _PickerField(
                      text: _endTime?.format(context) ?? 'End',
                      placeholder: _endTime == null,
                      icon: Icons.schedule,
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const _FieldLabel('Location'),
          TextField(
            controller: _locationController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration(
              hint: 'e.g. USJ-R Basak Pitch',
              suffix: const Icon(Icons.location_on_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 18),

          const _FieldLabel('Age Tiers'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('All Tiers'),
                selected: _allTiersSelected,
                onSelected: (_) => _toggleAllTiers(),
              ),
              for (final tier in AgeTier.values)
                FilterChip(
                  label: Text('${tier.label} · ${tier.ageLabel}'),
                  selected: _tiers.contains(tier),
                  onSelected: (_) => _toggleTier(tier),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _TierSelectionHint(tiers: _tiers),
          const SizedBox(height: 18),

          const _FieldLabel('Session Focus'),
          Wrap(
            spacing: 10,
            children: [
              for (final focus in SessionFocus.values)
                ChoiceChip(
                  label: Text(focus.label),
                  selected: _focus == focus,
                  onSelected: (_) => setState(() => _focus = focus),
                ),
            ],
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: isSaving ? null : _submit,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.event_available),
            label: Text(
              isSaving ? 'Scheduling…' : 'Create Schedule',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({required String hint, Widget? suffix}) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Confirms in words who the session will reach, under the tier chips. The
/// tiers gate which players can be marked present, so a wrong pick is only
/// caught later at the attendance screen — this states the consequence while
/// the coach is still looking at the control.
class _TierSelectionHint extends StatelessWidget {
  const _TierSelectionHint({required this.tiers});

  final Set<AgeTier> tiers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = tiers.isEmpty;

    final String message;
    if (empty) {
      message = 'Pick at least one tier — this decides who can attend.';
    } else if (tiers.length == AgeTier.values.length) {
      message = 'Open to every player in the academy.';
    } else {
      final names = AgeTier.values
          .where(tiers.contains)
          .map((t) => t.label)
          .join(' and ');
      message = 'Only $names players can be marked present.';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          empty ? Icons.error_outline : Icons.info_outline,
          size: 14,
          color: empty ? cs.error : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: empty ? cs.error : cs.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

/// An uppercase section label above a form field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A read-only, tappable field that opens a picker (date or time).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.text,
    required this.placeholder,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final bool placeholder;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: Icon(icon, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: placeholder ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
      ),
    );
  }
}
