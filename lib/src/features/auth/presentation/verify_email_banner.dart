import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/email_verification.dart';
import '../data/auth_repository.dart';
import 'verify_email_sheet.dart';

/// A quiet, persistent prompt shown to users whose email address isn't verified
/// yet. Creating a voice, generating a story and narrating one all need a
/// verified address, so this appears *before* they hit that wall rather than
/// leaving them to discover it as a failure.
///
/// Renders nothing once the address is verified, and nothing at all for Google
/// and Apple sign-ins (those providers assert the address themselves).
class VerifyEmailBanner extends ConsumerWidget {
  const VerifyEmailBanner({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(emailVerificationNeededProvider)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final email = ref.watch(authRepositoryProvider).currentUser?.email;
    return Padding(
      padding: margin,
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.secondaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showVerifyEmail(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mark_email_unread_outlined,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verify your email',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email == null
                            ? 'Tap the link we emailed you to start creating '
                                'voices and stories.'
                            : 'Tap the link we sent to $email to start creating '
                                'voices and stories.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ensures the user's email is verified before running [action].
///
/// This is the single choke point for flows that would otherwise fail at the
/// backend: it opens the verify sheet, and only proceeds once the address comes
/// back verified. Returns false when the user backed out still unverified.
Future<bool> ensureEmailVerified(BuildContext context, WidgetRef ref) async {
  if (!ref.read(emailVerificationNeededProvider)) return true;
  return showVerifyEmail(context);
}
