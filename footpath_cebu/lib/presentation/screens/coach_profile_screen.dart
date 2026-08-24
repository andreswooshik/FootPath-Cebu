import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/profile_photo_controller.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/change_password_screen.dart';
import 'package:footpath_cebu/presentation/screens/dispute_list_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

/// Coach Portal — the signed-in coach's own profile.
///
/// A thin View: it renders the shared [squadProvider] snapshot and forwards
/// intent (refresh, reset password, sign out). No data access lives here.
class CoachProfileScreen extends ConsumerStatefulWidget {
  const CoachProfileScreen({super.key, required this.profile});

  /// The signed-in user, handed down from the login flow.
  final UserProfile profile;

  @override
  ConsumerState<CoachProfileScreen> createState() => _CoachProfileScreenState();
}

class _CoachProfileScreenState extends ConsumerState<CoachProfileScreen> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  @override
  void didUpdateWidget(covariant CoachProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) _profile = widget.profile;
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;
      final contentType = _photoContentType(picked);
      if (contentType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only JPEG, PNG, and WebP photos are allowed.'),
          ),
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final updated = await ref
          .read(profilePhotoControllerProvider.notifier)
          .submit(
            _profile,
            bytes: bytes,
            filename: picked.name,
            contentType: contentType,
          );
      if (!mounted) return;
      if (updated == null) {
        final error = ref.read(profilePhotoControllerProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(error, 'Could not upload the photo.'),
            ),
          ),
        );
        return;
      }
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your profile photo was updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the selected photo.')),
      );
    }
  }

  String? _photoContentType(XFile file) {
    final declared = file.mimeType?.split(';').first.trim().toLowerCase();
    if (declared == 'image/jpeg' ||
        declared == 'image/png' ||
        declared == 'image/webp') {
      return declared;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(unregisterDeviceProvider)();
    await ref.read(signOutProvider)();
    if (!mounted) return;
    // Clear the whole stack so Back cannot return to the signed-in portal.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(squadProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _IdentityHeader(
              profile: _profile,
              uploading: ref.watch(profilePhotoControllerProvider).isLoading,
              onUpload: _pickAndUploadPhoto,
            ),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Squad Snapshot'),
            const SizedBox(height: 8),
            _squadSnapshot(),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Disputes'),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Disputes'),
                subtitle: const Text('Flagged issues and their threads'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DisputeListScreen()),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Account'),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_reset_outlined),
                title: const Text('Change password'),
                subtitle: const Text('Requires your current password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordScreen(email: _profile.email),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    ).animateScreenEntrance();
  }

  Widget _squadSnapshot() {
    return ref
        .watch(squadProvider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: DashboardLoadingState(compact: true, shrinkWrap: true),
          ),
          error: (e, _) => DashboardErrorState(
            message: friendlyErrorMessage(
              e,
              'Something went wrong loading your squad.',
            ),
            onRetry: () => ref.invalidate(squadProvider),
          ),
          data: (squad) {
            // Players cleared by School Staff to play, and players on an
            // academic warning or blocked from selection.
            final eligible = squad
                .where((p) => p.eligibility == EligibilityStatus.eligible)
                .length;
            final needsAttention = squad
                .where(
                  (p) =>
                      p.eligibility == EligibilityStatus.academicWarning ||
                      p.eligibility == EligibilityStatus.notEligible,
                )
                .length;
            return Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.groups_outlined,
                    label: 'Registered',
                    value: '${squad.length}',
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    icon: Icons.verified_outlined,
                    label: 'Eligible',
                    value: '$eligible',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    icon: Icons.warning_amber_rounded,
                    label: 'Needs Attention',
                    value: '$needsAttention',
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            );
          },
        );
  }
}

/// The coach's avatar, name, email and role.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.profile,
    required this.uploading,
    required this.onUpload,
  });

  final UserProfile profile;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.name.isNotEmpty
        ? profile.name[0].toUpperCase()
        : '?';
    return Column(
      children: [
        _CoachAvatar(profile: profile, initial: initial),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('upload-coach-photo'),
          onPressed: uploading ? null : onUpload,
          icon: uploading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_a_photo_outlined),
          label: Text(
            uploading ? 'Uploading photo...' : 'Update profile photo',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          profile.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          profile.email,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        Chip(
          avatar: const Icon(Icons.sports_soccer, size: 16),
          label: Text(profile.displayRole),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _CoachAvatar extends StatelessWidget {
  const _CoachAvatar({required this.profile, required this.initial});

  final UserProfile profile;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = CircleAvatar(
      radius: 44,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initial,
        style: theme.textTheme.headlineLarge?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    final url = profile.photoUrl;
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        cacheWidth: 264,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
