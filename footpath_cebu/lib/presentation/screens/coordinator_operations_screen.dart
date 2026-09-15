import 'package:flutter/material.dart';

import 'package:footpath_cebu/presentation/screens/coordinator_injuries_screen.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_matches_screen.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class CoordinatorOperationsScreen extends StatelessWidget {
  const CoordinatorOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Operations'),
      actions: const [NotificationBell()],
    ),
    body: ResponsiveContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            'Club workflows',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Complete reviews and record the information that keeps your club moving.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _OperationCard(
            icon: Icons.healing_outlined,
            title: 'Injury reviews',
            subtitle:
                'Confirm reports and recovery updates from the care team.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CoordinatorInjuriesScreen(),
              ),
            ),
          ),
          _OperationCard(
            icon: Icons.sports_score_outlined,
            title: 'Match statistics',
            subtitle:
                'Record matches, select rosters, and enter performance data.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CoordinatorMatchesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Member administration',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.manage_accounts_outlined),
              title: Text('Accounts and guardian links'),
              subtitle: Text(
                'Managed through the coordinator web portal while mobile management APIs are added.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon, size: 28),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
