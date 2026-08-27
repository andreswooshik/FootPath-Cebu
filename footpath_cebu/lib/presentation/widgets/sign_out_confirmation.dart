import 'package:flutter/material.dart';

/// Confirms the destructive session-ending action before account state is
/// cleared. Returns false when the dialog is dismissed by the system.
Future<bool> confirmSignOut(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text('You will need to sign in again to continue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ) ??
      false;
}
