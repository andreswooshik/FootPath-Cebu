import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_invite_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';

class CoordinatorCreateAccountScreen extends StatefulWidget {
  const CoordinatorCreateAccountScreen({super.key});
  @override
  State<CoordinatorCreateAccountScreen> createState() =>
      _CoordinatorCreateAccountScreenState();
}

class _CoordinatorCreateAccountScreenState
    extends State<CoordinatorCreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String _type = 'Player';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      title: const Text('Create account'),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Text(
          'Account type',
          style: TextStyle(color: Color(0xFF6B6A66), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final type in ['Player', 'Guardian', 'Coach'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TypeChip(
                    label: type,
                    selected: _type == type,
                    onTap: () => setState(() => _type = type),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _Field(
          label: 'Full name',
          hint: 'Juan Dela Cruz',
          controller: _nameController,
          required: true,
        ),
        if (_type == 'Player') ...[
          Row(
            children: [
              Expanded(
                child: _Field(label: 'Date of birth', hint: 'DD/MM/YYYY'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SelectField(label: 'Position', value: 'Winger'),
              ),
            ],
          ),
          _SelectField(label: 'Team', value: 'Boys U15'),
          const _Subsection('Guardian link'),
          const _SelectField(
            label: 'Linked guardian',
            value: 'Search existing guardians',
          ),
          const Text(
            "Can't find them? Create a new guardian account after saving this player.",
            style: TextStyle(color: Color(0xFF6B6A66), fontSize: 12),
          ),
        ] else if (_type == 'Guardian') ...[
          const _SelectField(label: 'Relationship to player', value: 'Parent'),
          const _SelectField(
            label: 'Linked player(s)',
            value: 'Search existing players',
          ),
        ] else ...[
          const _SelectField(label: 'Role', value: 'Head coach'),
          const _SelectField(label: 'Team assignment', value: 'Boys U15'),
        ],
        const _Subsection('Contact'),
        _Field(
          label: 'Phone number',
          hint: '+63 900 000 0000',
          controller: _phoneController,
          required: true,
        ),
        _Field(
          label: 'Email (optional)',
          hint: 'name@email.com',
          controller: _emailController,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _continueToInvite,
            child: Text('Create ${_type.toLowerCase()} account'),
          ),
        ),
      ],
      ),
    ),
  );

  void _continueToInvite() {
    if (!_formKey.currentState!.validate()) return;
    if (!useMockData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mobile account provisioning is being connected to the club server.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoordinatorInviteScreen(
          name: _nameController.text.trim(),
          accountType: _type,
          phone: _phoneController.text.trim(),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      backgroundColor: selected ? AppColors.tealLight : Colors.white,
      foregroundColor: selected ? AppColors.tealDark : const Color(0xFF6B6A66),
      side: BorderSide(
        color: selected ? AppColors.teal : const Color(0xFFE4E2DC),
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(label),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    this.controller,
    this.required = false,
  });
  final String label, hint;
  final TextEditingController? controller;
  final bool required;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? '$label is required.'
                : null
          : null,
    ),
  );
}

class _SelectField extends StatelessWidget {
  const _SelectField({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [DropdownMenuItem(value: value, child: Text(value))],
      onChanged: (_) {},
    ),
  );
}

class _Subsection extends StatelessWidget {
  const _Subsection(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );
}
