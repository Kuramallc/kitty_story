import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../common/errors.dart';
import '../../common/providers/firebase_providers.dart';
import '../community/data/community_repository.dart';
import '../player/application/shuffle_controller.dart';
import '../player/presentation/player_screen.dart';
import '../stories/data/story_repository.dart';
import '../stories/domain/story.dart';
import '../subscription/presentation/paywall_screen.dart';
import '../voices/data/voice_repository.dart';
import '../auth/data/auth_repository.dart';
import '../auth/presentation/verify_email_banner.dart';
import '../auth/presentation/verify_email_sheet.dart';
import '../../common/widgets/page_width.dart';

/// Signed-in landing screen. Becomes the voice-profiles + story-library home
/// in later phases; for now it confirms auth and links to the account screen.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _starting = false;

  /// Starts shuffling the user's own library: stories they generated plus the
  /// ones they saved from the community. Samples are deliberately excluded —
  /// "your stories" should mean theirs, and if they have none the right
  /// answer is to point them at making or saving one rather than quietly
  /// playing a stock story.
  Future<void> _shuffle() async {
    final controller = ref.read(shuffleControllerProvider);
    if (controller == null) return;
    setState(() => _starting = true);
    try {
      final voices = await ref.read(voiceRepositoryProvider).fetchVoices();
      if (!mounted) return;
      final ready = voices.where((v) => v.isReady).toList();
      if (ready.isEmpty) {
        await _promptForVoice();
        return;
      }

      final generated = await ref.read(storyRepositoryProvider).fetchGenerated();
      final saved = await ref.read(communityRepositoryProvider).fetchArchived();
      if (!mounted) return;
      final pool = <Story>[
        ...generated,
        ...saved.map((a) => a.toStory()),
      ];
      if (pool.isEmpty) {
        await _promptForStories();
        return;
      }

      final voice = ready.first;
      final repo = ref.read(storyRepositoryProvider);
      await controller.start(
        pool: pool,
        voiceId: voice.id,
        narrate: (story, voiceId) =>
            repo.synthesize(story: story, voiceId: voiceId),
        onError: (error) async {
          if (!mounted) return;
          if (await showVerifyEmailIfNeeded(context, error)) return;
          if (!mounted) return;
          if (await showPaywallIfQuota(context, error)) return;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not play: ${friendlyError(error)}')),
          );
        },
      );
      if (!mounted) return;
      final playing = controller.current;
      if (playing != null) {
        // No url: shuffle already loaded and started this story, and the
        // player must attach rather than reload. An empty string here would
        // be treated as a real url and clobber the audio.
        context.push('/player', extra: PlayerArgs(title: playing.title));
      }
    } catch (error) {
      if (!mounted) return;
      if (await showVerifyEmailIfNeeded(context, error)) return;
      if (!mounted) return;
      if (await showPaywallIfQuota(context, error)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start: ${friendlyError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _promptForVoice() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No ready voices'),
        content: const Text(
          'Record a family voice first, then stories can be read in it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add a voice'),
          ),
        ],
      ),
    );
    if (go == true && mounted) context.push('/voices/consent');
  }

  /// Nothing of their own to shuffle yet. Both routes out are offered rather
  /// than a dead end.
  Future<void> _promptForStories() async {
    final route = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No stories yet'),
        content: const Text(
          'Shuffle plays the stories you have made and the ones you have saved '
          'from the community.\n\n'
          'Create one in your story library, or explore the community and save '
          'a story another family shared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, '/explore'),
            child: const Text('Explore community'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, '/stories'),
            child: const Text('Story library'),
          ),
        ],
      ),
    );
    if (route != null && mounted) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
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
                        if (firebaseReady) ...[
                          const SizedBox(height: 24),
                          _ShuffleButton(
                            busy: _starting,
                            onPressed: _starting ? null : _shuffle,
                          ),
                        ],
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

/// The round shuffle button. Large and central because it is the one-tap
/// path to "just play something" — the thing a parent wants at bedtime with a
/// child already in bed.
class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 76,
          width: 76,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: busy
                ? const SizedBox(
                    height: 26,
                    width: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.play_arrow, size: 38),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          busy ? 'Starting…' : 'Shuffle my stories',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
