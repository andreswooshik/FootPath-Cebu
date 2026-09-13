import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/player_registration_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/registration_forms.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class CoordinatorPlayerRegistrationFlow extends ConsumerWidget {
  const CoordinatorPlayerRegistrationFlow({
    super.key,
    required this.onAccountTypeChanged,
  });
  final ValueChanged<String> onAccountTypeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerRegistrationControllerProvider);
    final controller = ref.read(playerRegistrationControllerProvider.notifier);
    final canPop =
        !state.isBusy &&
        (state.step == RegistrationStep.guardianQuestion ||
            state.step == RegistrationStep.success);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) controller.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (state.step) {
            RegistrationStep.guardianQuestion => 'Create player account',
            RegistrationStep.existingGuardian => 'Select guardian',
            RegistrationStep.newGuardian => 'Guardian information',
            RegistrationStep.player => 'Player information',
            RegistrationStep.review => 'Review registration',
            RegistrationStep.success => 'Registration complete',
          }),
          leading: BackButton(
            onPressed: state.isBusy || state.retryOnly
                ? null
                : () {
                    if (controller.back()) Navigator.of(context).pop();
                  },
          ),
        ),
        body: ResponsiveContent(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.isBusy) const LinearProgressIndicator(),
              if (state.error != null) ...[
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (state.duplicateGuardianId != null)
                  TextButton.icon(
                    onPressed: () => controller.chooseGuardian(true),
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Use existing guardian'),
                  ),
                const SizedBox(height: 16),
              ],
              switch (state.step) {
                RegistrationStep.guardianQuestion => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Player', label: Text('Player')),
                        ButtonSegment(
                          value: 'Guardian',
                          label: Text('Guardian'),
                        ),
                        ButtonSegment(value: 'Coach', label: Text('Coach')),
                      ],
                      selected: const {'Player'},
                      onSelectionChanged: (value) =>
                          onAccountTypeChanged(value.first),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Does this player already have a guardian account?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => controller.chooseGuardian(true),
                      child: const Text('Yes'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => controller.chooseGuardian(false),
                      child: const Text('No'),
                    ),
                  ],
                ),
                RegistrationStep.existingGuardian => _GuardianSearch(
                  initialQuery: state.draft.guardian.email,
                  selectedId: state.draft.existingGuardian?.id,
                  onSelected: controller.selectGuardian,
                ),
                RegistrationStep.newGuardian => AbsorbPointer(
                  absorbing: state.isBusy,
                  child: GuardianRegistrationForm(
                    initial: state.draft.guardian,
                    busy: state.isBusy,
                    onChanged: controller.editGuardian,
                    onContinue: controller.continueGuardian,
                  ),
                ),
                RegistrationStep.player => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.family_restroom),
                      title: Text(state.draft.guardianName),
                      subtitle: Text(state.draft.guardianEmail),
                    ),
                    const SizedBox(height: 16),
                    PlayerAccountForm(
                      initial: state.draft.player,
                      onChanged: controller.editPlayer,
                      onContinue: controller.review,
                    ),
                  ],
                ),
                RegistrationStep.review => _Review(
                  state: state,
                  onSubmit: controller.submit,
                ),
                RegistrationStep.success => _Success(state: state),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardianSearch extends ConsumerStatefulWidget {
  const _GuardianSearch({
    required this.initialQuery,
    this.selectedId,
    required this.onSelected,
  });
  final String initialQuery;
  final String? selectedId;
  final ValueChanged<ClubMember> onSelected;
  @override
  ConsumerState<_GuardianSearch> createState() => _GuardianSearchState();
}

class _GuardianSearchState extends ConsumerState<_GuardianSearch> {
  late final _search = TextEditingController(text: widget.initialQuery);
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guardians = ref.watch(clubMembersProvider(ClubMemberRole.guardian));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search guardians',
            hintText: 'Name, email or mobile number',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        guardians.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => DashboardErrorState(
            message: friendlyErrorMessage(error, 'Could not load guardians.'),
            onRetry: () =>
                ref.invalidate(clubMembersProvider(ClubMemberRole.guardian)),
          ),
          data: (members) {
            final query = _search.text.trim().toLowerCase();
            final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
            final matches = members
                .where(
                  (m) =>
                      m.name.toLowerCase().contains(query) ||
                      m.email.toLowerCase().contains(query) ||
                      (digits.isNotEmpty &&
                          m.mobileNumber
                              .replaceAll(RegExp(r'[^0-9]'), '')
                              .contains(
                                digits.replaceFirst(RegExp(r'^0'), '63'),
                              )),
                )
                .toList();
            if (matches.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No matching guardians.'),
              );
            }
            return Column(
              children: [
                for (final guardian in matches)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(guardian.name),
                    subtitle: Text(
                      [
                        guardian.email,
                        if (guardian.mobileNumber.isNotEmpty)
                          guardian.mobileNumber,
                        if (guardian.linkedPlayers.isNotEmpty)
                          guardian.linkedPlayers.join(', '),
                      ].join('\n'),
                    ),
                    trailing: Icon(
                      guardian.id == widget.selectedId
                          ? Icons.check_circle_outline
                          : Icons.chevron_right,
                    ),
                    onTap: () => widget.onSelected(guardian),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.onSubmit});
  final RegistrationState state;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Player', style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(state.draft.player.name),
        subtitle: Text(
          '${MaterialLocalizations.of(context).formatMediumDate(state.draft.player.dateOfBirth!)}\nGuardian-managed profile',
        ),
      ),
      const Divider(),
      Text(
        state.draft.existingGuardian == null
            ? 'New guardian'
            : 'Existing guardian',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(state.draft.guardianName),
        subtitle: Text(
          '${state.draft.guardianEmail}\n${state.draft.existingGuardian?.mobileNumber ?? state.draft.guardian.mobileNumber}',
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: state.isBusy ? null : onSubmit,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(
          state.isBusy
              ? 'Creating account and player profile...'
              : state.retryOnly
              ? 'Retry registration'
              : 'Create player profile',
        ),
      ),
    ],
  );
}

class _Success extends StatelessWidget {
  const _Success({required this.state});
  final RegistrationState state;
  @override
  Widget build(BuildContext context) {
    final result = state.result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, size: 48),
        const SizedBox(height: 16),
        Text(
          result.guardianCreated
              ? 'Guardian account and player profile created successfully.'
              : 'Player profile added successfully.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          result.guardianCreated
              ? 'Guardian account created and linked successfully.'
              : 'Linked to ${state.draft.guardianName}.',
        ),
        if (result.guardianTemporaryPassword != null) ...[
          const SizedBox(height: 20),
          Text('Guardian: ${result.guardianEmail}'),
          SelectableText(
            'Temporary password: ${result.guardianTemporaryPassword}',
          ),
        ],
        if (result.replayed) ...[
          const SizedBox(height: 16),
          const Text(
            'Registration was already completed. For new login accounts, use Forgot password to set a password if access details were not received.',
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(result),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
