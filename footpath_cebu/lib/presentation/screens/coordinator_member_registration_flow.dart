import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/presentation/providers/member_registration_provider.dart';
import 'package:footpath_cebu/presentation/widgets/registration_forms.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

enum MemberRegistrationPurpose { standalone, playerRegistration }

class CoordinatorMemberRegistrationFlow extends ConsumerWidget {
  const CoordinatorMemberRegistrationFlow({
    super.key,
    required this.role,
    required this.onAccountTypeChanged,
    this.purpose = MemberRegistrationPurpose.standalone,
    this.onBack,
    this.onCreated,
  }) : assert(
         purpose == MemberRegistrationPurpose.standalone ||
             role == MemberAccountRole.guardian,
       ),
       assert(
         purpose == MemberRegistrationPurpose.standalone || onBack != null,
       ),
       assert(
         purpose == MemberRegistrationPurpose.standalone || onCreated != null,
       );

  final MemberAccountRole role;
  final ValueChanged<String> onAccountTypeChanged;
  final MemberRegistrationPurpose purpose;
  final VoidCallback? onBack;
  final ValueChanged<MemberRegistrationResult>? onCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memberRegistrationControllerProvider);
    final controller = ref.read(memberRegistrationControllerProvider.notifier);
    final isPlayerRegistration =
        purpose == MemberRegistrationPurpose.playerRegistration;

    void leave() {
      controller.reset();
      if (isPlayerRegistration) {
        onBack!();
      } else {
        Navigator.of(context).pop();
      }
    }

    ref.listen(memberRegistrationControllerProvider, (previous, next) {
      if (isPlayerRegistration &&
          previous?.result == null &&
          next.result != null) {
        onCreated!(next.result!);
      }
    });

    return PopScope(
      canPop: !state.isBusy && !isPlayerRegistration,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !state.isBusy && isPlayerRegistration) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: state.isBusy ? null : leave),
          title: Text(
            state.result == null
                ? 'Create ${role.label.toLowerCase()} account'
                : '${role.label} created',
          ),
        ),
        body: ResponsiveContent(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.isBusy) const LinearProgressIndicator(),
              if (state.result case final result?) ...[
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  '${result.role.label} account created successfully.',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(result.name, textAlign: TextAlign.center),
                Text(result.email, textAlign: TextAlign.center),
                if (result.temporaryPassword != null) ...[
                  const SizedBox(height: 20),
                  const Text('Temporary password'),
                  SelectableText(result.temporaryPassword!),
                ],
                if (result.replayed) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'This account was already created. Use Forgot password if the temporary password was not received.',
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(result),
                  child: const Text('Done'),
                ),
              ] else ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Player', label: Text('Player')),
                    ButtonSegment(value: 'Guardian', label: Text('Guardian')),
                    ButtonSegment(value: 'Coach', label: Text('Coach')),
                  ],
                  selected: {role.label},
                  onSelectionChanged: state.isBusy || isPlayerRegistration
                      ? null
                      : (selection) {
                          controller.reset();
                          onAccountTypeChanged(selection.first);
                        },
                ),
                const SizedBox(height: 24),
                if (state.error != null) ...[
                  Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                AbsorbPointer(
                  absorbing: state.isBusy,
                  child: MemberRegistrationForm(
                    key: ValueKey(role),
                    role: role,
                    busy: state.isBusy,
                    onSubmit: (data) => controller.submit(role, data),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
