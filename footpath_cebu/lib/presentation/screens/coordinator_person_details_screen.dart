import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/coordinator_people_repository.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';
import 'package:footpath_cebu/presentation/providers/coordinator_people_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class CoordinatorPersonDetailsScreen extends ConsumerStatefulWidget {
  const CoordinatorPersonDetailsScreen({
    super.key,
    required this.role,
    required this.personId,
  });

  final CoordinatorPersonRole role;
  final String personId;

  @override
  ConsumerState<CoordinatorPersonDetailsScreen> createState() =>
      _CoordinatorPersonDetailsScreenState();
}

class _CoordinatorPersonDetailsScreenState
    extends ConsumerState<CoordinatorPersonDetailsScreen> {
  bool _deleting = false;

  CoordinatorPersonKey get _key =>
      CoordinatorPersonKey(widget.role, widget.personId);

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(coordinatorPersonDetailsProvider(_key));
    return Scaffold(
      appBar: AppBar(title: Text('${widget.role.label} Details')),
      body: details.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: _errorText(error, 'Could not load these details.'),
          onRetry: () => ref.invalidate(coordinatorPersonDetailsProvider(_key)),
        ),
        data: (person) => Stack(
          children: [
            RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(coordinatorPersonDetailsProvider(_key).future),
              child: ResponsiveContent(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  children: [
                    _PersonHeading(person: person),
                    const SizedBox(height: 24),
                    _Section(
                      title: 'Personal information',
                      children: [
                        _DetailRow(
                          label: 'First name',
                          value: person.firstName,
                        ),
                        _DetailRow(
                          label: 'Middle initial',
                          value: person.middleInitial,
                        ),
                        _DetailRow(label: 'Last name', value: person.lastName),
                        if (person.role == CoordinatorPersonRole.player) ...[
                          _DetailRow(
                            label: 'Date of birth',
                            value: _formatDate(person.dateOfBirth),
                          ),
                          _DetailRow(
                            label: 'Age',
                            value: person.age?.toString() ?? '',
                          ),
                        ],
                      ],
                    ),
                    if (person.role != CoordinatorPersonRole.player) ...[
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Contact information',
                        children: [
                          _DetailRow(label: 'Email', value: person.email),
                          _DetailRow(
                            label: 'Mobile number',
                            value: person.mobileNumber,
                          ),
                        ],
                      ),
                    ],
                    if (person.role == CoordinatorPersonRole.player) ...[
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Football information',
                        children: [
                          _DetailRow(
                            label: 'Age tier',
                            value: person.ageTierDisplay,
                          ),
                          _DetailRow(
                            label: 'Position',
                            value: _positionLabel(person.position),
                          ),
                          _DetailRow(
                            label: 'Class year',
                            value: person.classYear,
                          ),
                        ],
                      ),
                    ],
                    if (person.role != CoordinatorPersonRole.coach) ...[
                      const SizedBox(height: 20),
                      _LinkedPeopleSection(
                        title: person.role == CoordinatorPersonRole.guardian
                            ? 'Linked players'
                            : 'Guardian',
                        emptyMessage:
                            person.role == CoordinatorPersonRole.guardian
                            ? 'No players linked to this guardian.'
                            : 'No guardian linked to this player.',
                        people: person.linkedPeople,
                        linkedRole:
                            person.role == CoordinatorPersonRole.guardian
                            ? CoordinatorPersonRole.player
                            : CoordinatorPersonRole.guardian,
                        onOpen: _openLinkedPerson,
                      ),
                    ],
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: _deleting
                          ? null
                          : () => _confirmDelete(person),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        person.role == CoordinatorPersonRole.player
                            ? 'Delete Player'
                            : 'Delete Account',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_deleting)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLinkedPerson(
    CoordinatorPersonRole role,
    CoordinatorPersonReference person,
  ) async {
    final deletedRole = await Navigator.of(context).push<CoordinatorPersonRole>(
      MaterialPageRoute(
        builder: (_) =>
            CoordinatorPersonDetailsScreen(role: role, personId: person.id),
      ),
    );
    if (deletedRole == null || !mounted) return;
    _invalidatePeople();
    ref.invalidate(coordinatorPersonDetailsProvider(_key));
    _showDeletionSuccess(deletedRole);
  }

  Future<void> _confirmDelete(CoordinatorPersonDetails person) async {
    if (_deleting) return;
    final label = person.role == CoordinatorPersonRole.player
        ? 'player profile'
        : 'account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          person.role == CoordinatorPersonRole.player
              ? 'Delete Player?'
              : 'Delete ${person.role.label} Account?',
        ),
        content: Text(
          "Are you sure you want to delete ${person.name}'s $label? "
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref
          .read(coordinatorPeopleRepositoryProvider)
          .deletePerson(person.role, person.id);
      if (!mounted) return;
      _invalidatePeople();
      Navigator.of(context).pop(person.role);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorText(error, 'Could not delete this person.')),
        ),
      );
    }
  }

  void _invalidatePeople() {
    ref.invalidate(squadProvider);
    ref.invalidate(clubMembersProvider(ClubMemberRole.guardian));
    ref.invalidate(clubMembersProvider(ClubMemberRole.coach));
  }

  void _showDeletionSuccess(CoordinatorPersonRole role) {
    final message = role == CoordinatorPersonRole.player
        ? 'Player deleted successfully.'
        : '${role.label} account deleted successfully.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PersonHeading extends StatelessWidget {
  const _PersonHeading({required this.person});

  final CoordinatorPersonDetails person;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 30,
        backgroundColor: person.role == CoordinatorPersonRole.guardian
            ? AppColors.coral
            : AppColors.teal,
        foregroundColor: Colors.white,
        child: Text(_initials(person.name)),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(person.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 3),
            Text(
              person.role.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value.trim().isEmpty ? 'Not provided' : value)),
      ],
    ),
  );
}

class _LinkedPeopleSection extends StatelessWidget {
  const _LinkedPeopleSection({
    required this.title,
    required this.emptyMessage,
    required this.people,
    required this.linkedRole,
    required this.onOpen,
  });

  final String title;
  final String emptyMessage;
  final List<CoordinatorPersonReference> people;
  final CoordinatorPersonRole linkedRole;
  final void Function(
    CoordinatorPersonRole role,
    CoordinatorPersonReference person,
  )
  onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: people.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  emptyMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : Column(
                children: [
                  for (var index = 0; index < people.length; index++) ...[
                    ListTile(
                      title: Text(people[index].name),
                      subtitle: people[index].email.isEmpty
                          ? null
                          : Text(people[index].email),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onOpen(linkedRole, people[index]),
                    ),
                    if (index != people.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
      ),
    ],
  );
}

String _errorText(Object error, String fallback) =>
    error is CoordinatorPeopleRepositoryException ? error.message : fallback;

String _formatDate(DateTime? value) {
  if (value == null) return '';
  const months = [
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
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _positionLabel(String? code) {
  if (code == null || code.isEmpty) return '';
  for (final position in PlayerPosition.values) {
    if (position.code == code) return position.labelWithCode;
  }
  return code;
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();
