import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/club_registration_controller.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';

class CoachLicenseSelection {
  const CoachLicenseSelection({
    required this.bytes,
    required this.filename,
    required this.extension,
  });

  final Uint8List bytes;
  final String filename;
  final String? extension;
}

typedef CoachLicensePicker = Future<CoachLicenseSelection?> Function();

class ClubRegistrationScreen extends ConsumerStatefulWidget {
  const ClubRegistrationScreen({super.key, this.pickCoachLicense});

  final CoachLicensePicker? pickCoachLicense;

  @override
  ConsumerState<ClubRegistrationScreen> createState() =>
      _ClubRegistrationScreenState();
}

class _ClubRegistrationScreenState
    extends ConsumerState<ClubRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clubName = TextEditingController();
  final _coordinatorName = TextEditingController();
  final _headCoachName = TextEditingController();
  final _cvfaMembership = TextEditingController();
  final _schoolName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _isSchoolAffiliated = false;

  @override
  void dispose() {
    _clubName.dispose();
    _coordinatorName.dispose();
    _headCoachName.dispose();
    _cvfaMembership.dispose();
    _schoolName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _pickLicense() async {
    try {
      final selection =
          await (widget.pickCoachLicense?.call() ??
              _pickCoachLicenseFromDevice());
      if (selection == null || !mounted) return;
      ref
          .read(clubRegistrationControllerProvider.notifier)
          .setLicense(
            bytes: selection.bytes,
            filename: selection.filename,
            extension: selection.extension,
          );
    } catch (_) {
      if (mounted) {
        ref
            .read(clubRegistrationControllerProvider.notifier)
            .setFilePickerError();
      }
    }
  }

  Future<CoachLicenseSelection?> _pickCoachLicenseFromDevice() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose coach license',
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (file == null) return null;
    return CoachLicenseSelection(
      bytes: await file.readAsBytes(),
      filename: file.name,
      extension: file.extension,
    );
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    final result = await ref
        .read(clubRegistrationControllerProvider.notifier)
        .submit(
          clubName: _clubName.text,
          coordinatorName: _coordinatorName.text,
          headCoachName: _headCoachName.text,
          cvfaMembership: _cvfaMembership.text,
          isSchoolAffiliated: _isSchoolAffiliated,
          schoolName: _schoolName.text,
          email: _email.text,
          password: _password.text,
        );
    if (!mounted || result == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ClubRegistrationSuccessScreen(
          coordinatorEmail: result.coordinatorEmail,
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required.';
    final email = value.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    return null;
  }

  String? _confirmationValidator(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your password.';
    if (value != _password.text) return 'Passwords do not match.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clubRegistrationControllerProvider);
    final controller = ref.read(clubRegistrationControllerProvider.notifier);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Club Registration')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'CLUB REGISTRATION',
                        style: TextStyle(
                          color: AppColors.tealDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Apply to join FootPath',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Register your club and proposed Club Coordinator. A FootPath administrator will review the application before portal and mobile access are enabled.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _field(
                        key: const Key('club-name-field'),
                        controller: _clubName,
                        label: 'Club name',
                        maxLength: 120,
                        error: state.fieldErrors['club_name'],
                        onChanged: (_) =>
                            controller.clearFieldError('club_name'),
                      ),
                      _field(
                        controller: _coordinatorName,
                        label: 'Name of the coordinator',
                        maxLength: 150,
                        error: state.fieldErrors['coordinator_name'],
                        onChanged: (_) =>
                            controller.clearFieldError('coordinator_name'),
                      ),
                      _field(
                        controller: _headCoachName,
                        label: 'Head coach name',
                        maxLength: 150,
                        error: state.fieldErrors['head_coach_name'],
                        onChanged: (_) =>
                            controller.clearFieldError('head_coach_name'),
                      ),
                      Text(
                        'Coach license',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('coach-license-picker'),
                        onPressed: state.isSubmitting ? null : _pickLicense,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(
                          state.license == null ? 'Choose file' : 'Change file',
                        ),
                      ),
                      if (state.license != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: AppColors.tealDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(state.license!.filename)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        state.fieldErrors['coach_license'] ??
                            'JPG, PNG or PDF, max 50 MB.',
                        key: const Key('coach-license-help'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: state.fieldErrors.containsKey('coach_license')
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _field(
                        controller: _cvfaMembership,
                        label: 'CVFA membership number',
                        maxLength: 80,
                        error: state.fieldErrors['cvfa_membership'],
                        onChanged: (_) =>
                            controller.clearFieldError('cvfa_membership'),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'This club is affiliated with a school',
                        ),
                        value: _isSchoolAffiliated,
                        onChanged: state.isSubmitting
                            ? null
                            : (value) => setState(() {
                                _isSchoolAffiliated = value ?? false;
                                if (!_isSchoolAffiliated) {
                                  _schoolName.clear();
                                  controller.clearFieldError('school_name');
                                }
                              }),
                      ),
                      if (_isSchoolAffiliated)
                        _field(
                          key: const Key('school-name-field'),
                          controller: _schoolName,
                          label: 'School name',
                          maxLength: 150,
                          error: state.fieldErrors['school_name'],
                          onChanged: (_) =>
                              controller.clearFieldError('school_name'),
                        ),
                      const SizedBox(height: 4),
                      _field(
                        controller: _email,
                        label: 'Coordinator email',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: _emailValidator,
                        error: state.fieldErrors['email'],
                        onChanged: (_) => controller.clearFieldError('email'),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: const Key('registration-password-field'),
                        controller: _password,
                        obscureText: !state.showPassword,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: _passwordValidator,
                        onChanged: (_) =>
                            controller.clearFieldError('password1'),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          errorText: state.fieldErrors['password1'],
                          suffixIcon: IconButton(
                            tooltip: state.showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: controller.togglePassword,
                            icon: Icon(
                              state.showPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('registration-confirm-password-field'),
                        controller: _confirmation,
                        obscureText: !state.showConfirmation,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        validator: _confirmationValidator,
                        onFieldSubmitted: (_) =>
                            state.isSubmitting ? null : _submit(),
                        onChanged: (_) =>
                            controller.clearFieldError('password2'),
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          errorText: state.fieldErrors['password2'],
                          suffixIcon: IconButton(
                            tooltip: state.showConfirmation
                                ? 'Hide password confirmation'
                                : 'Show password confirmation',
                            onPressed: controller.toggleConfirmation,
                            icon: Icon(
                              state.showConfirmation
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            state.error!,
                            key: const Key('registration-error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const Key('submit-club-application'),
                          onPressed: state.isSubmitting ? null : _submit,
                          child: state.isSubmitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Submit application'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already approved?'),
                          TextButton(
                            onPressed: state.isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Log in'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    Key? key,
    required TextEditingController controller,
    required String label,
    int? maxLength,
    String? error,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: key,
      controller: controller,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction ?? TextInputAction.next,
      validator: validator ?? _required,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        errorText: error,
      ),
    ),
  );
}

class ClubRegistrationSuccessScreen extends StatelessWidget {
  const ClubRegistrationSuccessScreen({
    super.key,
    required this.coordinatorEmail,
  });

  final String coordinatorEmail;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(title: const Text('Application submitted')),
    body: SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.tealLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 36,
                    color: AppColors.tealDark,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Application submitted',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your club registration application has been submitted successfully. After approval, use this email and password in either the portal or mobile app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  coordinatorEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.login),
                    label: const Text('Back to login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
