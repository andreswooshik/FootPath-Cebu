import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/presentation/providers/session_confirmation_providers.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';

/// A Confirm/Confirmed toggle for one session, on the Player's schedule
/// card. Tapping records the player's RSVP; tapping again un-confirms.
class SessionConfirmationButton extends ConsumerWidget {
  const SessionConfirmationButton({
    super.key,
    required this.sessionId,
    required this.playerId,
  });

  final String sessionId;
  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmationsAsync = ref.watch(
      sessionConfirmationsProvider(playerId),
    );
    // Only spin this card's button — watch the in-flight set and check *this*
    // session, so a submit on one session doesn't light up every other card.
    final isSubmitting = ref
        .watch(sessionConfirmationControllerProvider)
        .contains(sessionId);

    return confirmationsAsync.when(
      // Nothing to show yet, but the card shouldn't jump around once the
      // list arrives — reserve the button's usual height.
      loading: () => const SizedBox(height: 36),
      error: (_, _) => const SizedBox.shrink(),
      data: (confirmations) {
        SessionConfirmation? mine;
        for (final c in confirmations) {
          if (c.sessionId == sessionId) mine = c;
        }
        final confirmed = mine?.status == ConfirmationStatus.confirmed;

        Future<void> respond(ConfirmationStatus status) async {
          await ref
              .read(sessionConfirmationControllerProvider.notifier)
              .submit(sessionId, playerId, status);
        }

        if (confirmed) {
          return OutlinedButton.icon(
            onPressed: isSubmitting
                ? null
                : () => respond(ConfirmationStatus.declined),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Confirmed'),
            // Text/icon inherit the theme's AA-safe default foreground; only
            // the outline itself carries the brand teal (a border only needs
            // the 3:1 non-text contrast minimum, which teal clears on white).
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.teal),
            ),
          );
        }
        return FilledButton(
          onPressed: isSubmitting
              ? null
              : () => respond(ConfirmationStatus.confirmed),
          child: isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm'),
        );
      },
    );
  }
}
