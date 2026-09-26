import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/widgets/parental_gate.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../../common/widgets/page_width.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _deleting = false;

  /// Two gates before an irreversible action: the grown-up check that guards
  /// every one-way door in the app, then an explicit confirmation spelling out
  /// exactly what disappears.
  Future<void> _deleteAccount() async {
    if (!await showParentalGate(context)) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently removes:\n\n'
          '• Your family voices, including the cloned voices held by our '
          'voice provider\n'
          '• Every story you have created, and their narration audio\n'
          '• Any stories, comments and likes you shared with the community\n'
          '• Your sign-in details\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // deleteAccount signs out, so the router drops us back to sign-in.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Your account and data have been deleted.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _deleting = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Could not delete the account: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authRepositoryProvider).currentUser;
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final entitlement = ref.watch(entitlementActiveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: PageWidth(
        maxWidth: kFormWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(user?.email ?? user?.displayName ?? 'Signed in'),
              subtitle: user == null ? null : Text('ID: ${user.uid}'),
            ),
            const Divider(height: 32),
            entitlement.maybeWhen(
              data: (active) => active
                  ? ListTile(
                      leading: Icon(
                        Icons.workspace_premium,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('Kitty Stories Unlimited'),
                      subtitle: const Text('Active — thank you! 💜'),
                    )
                  : ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: const Text('Upgrade to Unlimited'),
                      subtitle: const Text(
                        'Unlimited voices & stories · \$1.99/mo',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showPaywall(context),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: isLoading || _deleting
                  ? null
                  : () => ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            // Required in-app by App Store 5.1.1(v) and Google Play. Reachable
            // in two taps from the home screen — the guideline is about the exit
            // being as findable as the entrance, not just present.
            TextButton.icon(
              onPressed: _deleting ? null : _deleteAccount,
              icon: _deleting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.delete_forever_outlined,
                      color: theme.colorScheme.error,
                    ),
              label: Text(
                _deleting ? 'Deleting…' : 'Delete my account',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            Text(
              'Permanently deletes your voices, stories and sign-in details.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
