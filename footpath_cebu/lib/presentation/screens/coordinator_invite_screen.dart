import 'package:flutter/material.dart';

import 'package:footpath_cebu/presentation/theme/app_theme.dart';

class CoordinatorInviteScreen extends StatefulWidget {
  const CoordinatorInviteScreen({
    super.key,
    required this.name,
    required this.accountType,
    required this.phone,
  });
  final String name, accountType, phone;
  @override
  State<CoordinatorInviteScreen> createState() =>
      _CoordinatorInviteScreenState();
}

class _CoordinatorInviteScreenState extends State<CoordinatorInviteScreen> {
  int _method = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      title: const Text('Invite to FootPath'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.teal,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 16, color: Colors.white),
            ),
            Expanded(child: Container(height: 1, color: AppColors.teal)),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.tealLight,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.teal),
              ),
              child: const Center(
                child: Text(
                  '2',
                  style: TextStyle(color: AppColors.tealDark, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Profile saved. Now send access.',
          style: TextStyle(color: Color(0xFF6B6A66), fontSize: 12),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.tealLight,
            border: Border.all(color: AppColors.teal),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppColors.tealDark),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Created account',
                    style: TextStyle(color: AppColors.tealDark, fontSize: 12),
                  ),
                  Text(
                    widget.name,
                    style: const TextStyle(
                      color: AppColors.tealDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${widget.accountType} · Account created',
                    style: const TextStyle(
                      color: AppColors.tealDark,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'How should they get access?',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        _Option(
          index: 0,
          selected: _method == 0,
          title: 'Send invite link by SMS',
          detail: "They'll set their own password when they open it",
          onTap: () => setState(() => _method = 0),
        ),
        _Option(
          index: 1,
          selected: _method == 1,
          title: 'Send invite link by email',
          detail: 'Goes to the email on file, if provided',
          onTap: () => setState(() => _method = 1),
        ),
        _Option(
          index: 2,
          selected: _method == 2,
          title: 'Generate a temporary password',
          detail: 'Share it with them yourself, in person or by phone',
          onTap: () => setState(() => _method = 2),
        ),
        const SizedBox(height: 12),
        if (_method < 2) ...[
          TextFormField(
            initialValue: widget.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
          const SizedBox(height: 6),
          const Text(
            'The invite link expires in 7 days. You can resend it anytime from this player\'s profile.',
            style: TextStyle(color: Color(0xFF6B6A66), fontSize: 12),
          ),
        ] else
          const TextField(
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Temporary password',
              suffixIcon: Icon(Icons.copy_outlined),
            ),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: Text(
              _method == 2 ? 'Save temporary password' : 'Send invite',
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Skip for now'),
          ),
        ),
      ],
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.index,
    required this.selected,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final int index;
  final bool selected;
  final String title, detail;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: selected ? AppColors.teal : const Color(0xFFE4E2DC),
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.teal : const Color(0xFF6B6A66),
                width: 2,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF6B6A66),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
