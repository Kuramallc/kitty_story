import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/email_verification.dart';
import '../data/auth_repository.dart';

/// Shows the "verify your email" bottom sheet. Returns true once the address
/// came back verified, so the caller can carry on with what the user was doing.
Future<bool> showVerifyEmail(BuildContext context) async {
  final verified = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const VerifyEmailSheet(),
  );
  return verified ?? false;
}

/// If [error] is the backend's unverified-email rejection, show the sheet and
/// return true (handled). Otherwise return false so the caller falls back to
/// its own error handling — same contract as `showPaywallIfQuota`.
///
/// Matches on `details.reason`, not the message: the message is user-facing
/// copy and free to change (see `requireVerifiedEmail` in functions/src/auth.ts).
Future<bool> showVerifyEmailIfNeeded(BuildContext context, Object error) async {
  if (!isEmailNotVerified(error)) return false;
  await showVerifyEmail(context);
  return true;
}

/// Whether [error] is the backend's `email-not-verified` rejection.
bool isEmailNotVerified(Object error) {
  if (error is! FirebaseFunctionsException) return false;
  final details = error.details;
  return details is Map && details['reason'] == 'email-not-verified';
}

/// The verify-email panel. Used as a bottom sheet ([showVerifyEmail]) and
/// inline by the banner's expanded state.
class VerifyEmailSheet extends ConsumerStatefulWidget {
  const VerifyEmailSheet({super.key});

  @override
  ConsumerState<VerifyEmailSheet> createState() => _VerifyEmailSheetState();
}

class _VerifyEmailSheetState extends ConsumerState<VerifyEmailSheet> {
  bool _busy = false;
  String? _note;
  bool _noteIsError = false;

  void _setNote(String message, {bool isError = false}) {
    if (mounted) {
      setState(() {
        _note = message;
        _noteIsError = isError;
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await ref.read(emailVerificationNeededProvider.notifier).resend();
      _setNote('Sent. Check your inbox — and your spam folder.');
    } on FirebaseException catch (error) {
      _setNote(
        error.code == 'too-many-requests'
            ? 'We just sent one. Give it a minute before trying again.'
            : "Couldn't send it just now. Please try again shortly.",
        isError: true,
      );
    } catch (_) {
      _setNote("Couldn't send it just now. Please try again shortly.", isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final verified = await ref.read(emailVerificationNeededProvider.notifier).refresh();
      if (!mounted) return;
      if (verified) {
        if (navigator.canPop()) navigator.pop(true);
        return;
      }
      _setNote(
        "Not verified yet. Open the email and tap the link, then try again.",
        isError: true,
      );
    } catch (_) {
      _setNote("Couldn't check just now. Please try again in a moment.", isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(authRepositoryProvider).currentUser?.email;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_unread_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Verify your email',
              style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            email == null
                ? 'Tap the link in the email we sent you, then come back here.'
                : 'We sent a link to $email. Tap it, then come back here.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'This keeps family voices tied to a real address — it only takes a moment.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (_note != null) ...[
            const SizedBox(height: 16),
            Text(
              _note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _noteIsError ? theme.colorScheme.error : theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("I've verified — continue"),
          ),
          TextButton(
            onPressed: _busy ? null : _resend,
            child: const Text('Send the email again'),
          ),
        ],
      ),
    );
  }
}
