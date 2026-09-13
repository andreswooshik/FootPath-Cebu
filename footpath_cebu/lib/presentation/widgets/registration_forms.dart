import 'package:flutter/material.dart';
import 'package:footpath_cebu/domain/entities/player_registration.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';

String? registrationNameError(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

String? registrationEmailError(String? value, {bool optional = false}) {
  final email = value?.trim() ?? '';
  if (optional && email.isEmpty) return null;
  if (email.isEmpty) return 'Email is required.';
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address.';
}

String? registrationMiddleInitialError(String? value) {
  final initial = value?.trim() ?? '';
  if (initial.isEmpty) return null;
  return RegExp(r'^[A-Za-z]\.?$').hasMatch(initial)
      ? null
      : 'Enter one letter for the middle initial.';
}

String? registrationPhoneError(String? value) {
  final number = (value ?? '').replaceAll(RegExp(r'[\s()-]'), '');
  return RegExp(r'^(09\d{9}|\+?639\d{9})$').hasMatch(number)
      ? null
      : 'Enter a Philippine mobile number, e.g. 09171234567.';
}

class RegistrationField extends StatelessWidget {
  const RegistrationField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.validator,
    this.keyboardType,
    this.maxLength,
  });
  final String label, initialValue;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int? maxLength;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      validator: validator,
      keyboardType: keyboardType,
      maxLength: maxLength,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label, counterText: ''),
    ),
  );
}

class MemberRegistrationForm extends StatefulWidget {
  const MemberRegistrationForm({
    super.key,
    required this.role,
    required this.busy,
    required this.onSubmit,
  });

  final MemberAccountRole role;
  final bool busy;
  final ValueChanged<MemberRegistrationData> onSubmit;

  @override
  State<MemberRegistrationForm> createState() => _MemberRegistrationFormState();
}

class _MemberRegistrationFormState extends State<MemberRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  late final String _requestId = newRegistrationRequestId();
  String _first = '';
  String _middle = '';
  String _last = '';
  String _email = '';
  String _phone = '';

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RegistrationField(
          label: 'First name *',
          initialValue: _first,
          maxLength: 150,
          validator: registrationNameError,
          onChanged: (value) => _first = value,
        ),
        RegistrationField(
          label: 'Middle initial (optional)',
          initialValue: _middle,
          maxLength: 2,
          validator: registrationMiddleInitialError,
          onChanged: (value) => _middle = value,
        ),
        RegistrationField(
          label: 'Last name *',
          initialValue: _last,
          maxLength: 150,
          validator: registrationNameError,
          onChanged: (value) => _last = value,
        ),
        RegistrationField(
          label: 'Email *',
          initialValue: _email,
          maxLength: 254,
          keyboardType: TextInputType.emailAddress,
          validator: registrationEmailError,
          onChanged: (value) => _email = value,
        ),
        RegistrationField(
          label: 'Mobile number *',
          initialValue: _phone,
          maxLength: 30,
          keyboardType: TextInputType.phone,
          validator: registrationPhoneError,
          onChanged: (value) => _phone = value,
        ),
        FilledButton.icon(
          onPressed: widget.busy
              ? null
              : () {
                  if (!_formKey.currentState!.validate()) return;
                  widget.onSubmit(
                    MemberRegistrationData(
                      requestId: _requestId,
                      firstName: _first.trim(),
                      middleInitial: _middle
                          .trim()
                          .replaceAll('.', '')
                          .toUpperCase(),
                      lastName: _last.trim(),
                      email: _email.trim().toLowerCase(),
                      mobileNumber: _phone.trim(),
                    ),
                  );
                },
          icon: const Icon(Icons.person_add_outlined),
          label: Text(
            widget.busy
                ? 'Creating account...'
                : 'Create ${widget.role.label.toLowerCase()} account',
          ),
        ),
      ],
    ),
  );
}

/// The player section of the existing account form, now bound to real data.
class PlayerAccountForm extends StatefulWidget {
  const PlayerAccountForm({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onContinue,
  });
  final PlayerRegistrationData initial;
  final ValueChanged<PlayerRegistrationData> onChanged;
  final VoidCallback onContinue;
  @override
  State<PlayerAccountForm> createState() => _PlayerAccountFormState();
}

class _PlayerAccountFormState extends State<PlayerAccountForm> {
  final _formKey = GlobalKey<FormState>();
  late String _first = widget.initial.firstName,
      _last = widget.initial.lastName,
      _middle = widget.initial.middleInitial;
  late DateTime? _dob = widget.initial.dateOfBirth;
  void _changed() => widget.onChanged(
    PlayerRegistrationData(
      firstName: _first.trim(),
      lastName: _last.trim(),
      middleInitial: _middle.trim(),
      dateOfBirth: _dob,
    ),
  );
  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      children: [
        RegistrationField(
          label: 'First name',
          initialValue: _first,
          maxLength: 150,
          validator: registrationNameError,
          onChanged: (v) {
            _first = v;
            _changed();
          },
        ),
        RegistrationField(
          label: 'Last name',
          initialValue: _last,
          maxLength: 150,
          validator: registrationNameError,
          onChanged: (v) {
            _last = v;
            _changed();
          },
        ),
        RegistrationField(
          label: 'Middle initial (optional)',
          initialValue: _middle,
          maxLength: 5,
          onChanged: (v) {
            _middle = v;
            _changed();
          },
        ),
        FormField<DateTime>(
          initialValue: _dob,
          validator: (value) =>
              value == null ? 'Date of birth is required.' : null,
          builder: (field) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: () async {
                final now = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  initialDate:
                      _dob ?? DateTime(now.year - 12, now.month, now.day),
                  firstDate: DateTime(1900),
                  lastDate: now,
                );
                if (date == null || !mounted) return;
                setState(() => _dob = date);
                field.didChange(date);
                _changed();
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date of birth',
                  errorText: field.errorText,
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  _dob == null
                      ? 'Select date'
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(_dob!),
                ),
              ),
            ),
          ),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _changed();
              widget.onContinue();
            }
          },
          child: const Text('Review registration'),
        ),
      ],
    ),
  );
}
