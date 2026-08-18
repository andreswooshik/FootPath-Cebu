import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/screens/change_password_screen.dart';
import 'package:footpath_cebu/presentation/screens/guardian_privacy_pin_selection_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_privacy_pin_screen.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/widgets/eligibility_badge.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';

/// Profile tab — one player's avatar, attributes, and a log-out action.
/// Shared by the Player portal (viewing themselves) and the Guardian portal
/// (viewing their linked child) — [player] is resolved by whichever
/// dashboard hosts this screen.
class ProfileTabScreen extends ConsumerWidget {
  const ProfileTabScreen({
    super.key,
    required this.player,
    this.isGuardian = false,
  });

  final Player player;
  final bool isGuardian;

  bool get _isGoalkeeper => player.position?.group == PositionGroup.goalkeeper;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    ref.read(privacyUnlockedPlayersProvider.notifier).clear();
    await ref.read(signOutProvider)();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _guardianBody(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.family_restroom_outlined, size: 56),
        const SizedBox(height: 12),
        Text(
          'Guardian account',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Manage your household access without opening a player profile.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _PrivacyPinCard(player: player, isGuardian: true),
        const SizedBox(height: 24),
        Text('Account', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Change password'),
            subtitle: const Text('Requires your current password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
      ),
      body: isGuardian
          ? _guardianBody(context, ref)
          : PlayerPrivacyGate(
              player: player,
              isGuardian: isGuardian,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 40,
                          child: Icon(Icons.person, size: 40),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          player.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '${player.position?.labelWithCode ?? 'No position'} · '
                          '${player.ageTier.label}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        EligibilityBadge(
                          status: player.eligibility,
                          applicable: player.academicEligibilityApplicable,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Attributes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: _isGoalkeeper
                            ? [
                                _attributeRow('Diving', player.ratings.diving),
                                _attributeRow(
                                  'Handling',
                                  player.ratings.handling,
                                ),
                                _attributeRow(
                                  'Kicking',
                                  player.ratings.kicking,
                                ),
                                _attributeRow(
                                  'Reflexes',
                                  player.ratings.reflexes,
                                ),
                                _attributeRow('Speed', player.ratings.speed),
                                _attributeRow(
                                  'Positioning',
                                  player.ratings.positioning,
                                ),
                              ]
                            : [
                                _attributeRow('Pace', player.ratings.pace),
                                _attributeRow(
                                  'Shooting',
                                  player.ratings.shooting,
                                ),
                                _attributeRow(
                                  'Passing',
                                  player.ratings.passing,
                                ),
                                _attributeRow(
                                  'Dribbling',
                                  player.ratings.dribbling,
                                ),
                                _attributeRow(
                                  'Defending',
                                  player.ratings.defending,
                                ),
                                _attributeRow(
                                  'Physical',
                                  player.ratings.physical,
                                ),
                              ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _PrivacyPinCard(player: player, isGuardian: isGuardian),
                  const SizedBox(height: 24),
                  Text(
                    'Account',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // Acts on whoever is signed in (player or guardian), like Log out
                  // below — not on the viewed player.
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.lock_reset_outlined),
                      title: const Text('Change password'),
                      subtitle: const Text('Requires your current password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChangePasswordScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _signOut(context, ref),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ),
    ).animateScreenEntrance();
  }

  Widget _attributeRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value / 100, minHeight: 8),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _PrivacyPinCard extends ConsumerWidget {
  const _PrivacyPinCard({required this.player, required this.isGuardian});

  final Player player;
  final bool isGuardian;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MotionPress(
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(isGuardian ? 'Player privacy PIN' : 'Privacy PIN'),
          subtitle: Text(
            isGuardian
                ? 'Select a player to create or reset their PIN'
                : 'Create or change your 4–6 digit PIN',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => isGuardian
                    ? const GuardianPrivacyPinSelectionScreen()
                    : PlayerPrivacyPinScreen(player: player),
              ),
            );
          },
        ),
      ),
    );
  }
}
