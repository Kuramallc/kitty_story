import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common/providers/firebase_providers.dart';
import '../auth/data/auth_repository.dart';
import '../auth/presentation/verify_email_banner.dart';
import '../../common/widgets/page_width.dart';

/// Signed-in landing screen. Becomes the voice-profiles + story-library home
/// in later phases; for now it confirms auth and links to the account screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final user = firebaseReady
        ? ref.watch(authRepositoryProvider).currentUser
        : null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitty Stories'),
        actions: [
          if (firebaseReady)
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Account',
              onPressed: () => context.push('/account'),
            ),
        ],
      ),
      body: SafeArea(
        child: PageWidth(
          maxWidth: kFormWidth,
          // Scrolls only when the content cannot fit — otherwise the Spacers
          // keep it centred exactly as before. Needed because constraining the
          // width makes the copy wrap onto more lines, which overflows a short
          // viewport (a landscape phone, or a widget test's 800x600 surface).
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        Icon(
                          Icons.nightlight_round,
                          size: 96,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Kitty Stories',
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user?.email != null
                              ? 'Signed in as ${user!.email}'
                              : 'Bedtime stories told in the voices your child loves.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(),
                        if (!firebaseReady) ...[
                          const _SetupNotice(),
                          const SizedBox(height: 16),
                        ],
                        if (firebaseReady)
                          const VerifyEmailBanner(
                            margin: EdgeInsets.only(bottom: 16),
                          ),
                        FilledButton.icon(
                          onPressed: firebaseReady
                              ? () => context.push('/stories')
                              : null,
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Story library'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: firebaseReady
                              ? () => context.push('/explore')
                              : null,
                          icon: const Icon(Icons.travel_explore),
                          label: const Text('Explore community'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: firebaseReady
                              ? () => context.push('/voices')
                              : null,
                          icon: const Icon(Icons.record_voice_over_outlined),
                          label: const Text('Family voices'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown until Firebase is configured (`flutterfire configure`).
class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.build_circle_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Firebase isn\'t configured yet. Run `flutterfire configure`, '
                'then restart the app. See SETUP.md.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
