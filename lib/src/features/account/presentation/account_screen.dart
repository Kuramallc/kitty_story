import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/presentation/paywall_screen.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authRepositoryProvider).currentUser;
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final entitlement = ref.watch(entitlementActiveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
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
                    leading: Icon(Icons.workspace_premium,
                        color: theme.colorScheme.primary),
                    title: const Text('Kitty Story Unlimited'),
                    subtitle: const Text('Active — thank you! 💜'),
                  )
                : ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('Upgrade to Unlimited'),
                    subtitle: const Text('Unlimited voices & stories · \$1.99/mo'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showPaywall(context),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: isLoading
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
