import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/screens/player_privacy_pin_screen.dart';

/// Netflix-style player picker for guardian PIN management.
class GuardianPrivacyPinSelectionScreen extends ConsumerWidget {
  const GuardianPrivacyPinSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(linkedPlayersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Player privacy PINs')),
      body: players.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(linkedPlayersProvider),
            child: Text(friendlyErrorMessage(error, 'Could not load players.')),
          ),
        ),
        data: (children) => children.isEmpty
            ? const Center(child: Text('No linked players yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: children.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final child = children[index];
                  final status = ref.watch(
                    playerPrivacyPinStatusProvider(child.id),
                  );
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        radius: 28,
                        child: Text(
                          child.name.isEmpty
                              ? '?'
                              : child.name[0].toUpperCase(),
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      title: Text(
                        child.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: status.when(
                        loading: () => const Text('Checking PIN status…'),
                        error: (_, _) => const Text('PIN status unavailable'),
                        data: (value) => Text(
                          value.hasPin
                              ? 'PIN set · tap to manage'
                              : 'No PIN set · tap to create one',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlayerPrivacyPinScreen(
                            player: child,
                            isGuardian: true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
