import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/verify_email_sheet.dart';
import '../../stories/data/story_repository.dart';
import '../../stories/domain/story.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../voices/data/voice_repository.dart';
import '../../voices/domain/voice_profile.dart';
import 'player_screen.dart';
import '../../../common/errors.dart';

/// Shared flow: pick a ready cloned voice (prompting to record one if there are
/// none), synthesize [story] in it, and open the bedtime player. Used by both
/// the generated-story and community-story detail screens.
Future<void> tellStoryInVoice(
  BuildContext context,
  WidgetRef ref,
  Story story,
  String title,
) async {
  final List<VoiceProfile> voices;
  try {
    voices = await ref.read(voiceRepositoryProvider).fetchVoices();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load your voices: ${friendlyError(error)}')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final ready = voices.where((v) => v.isReady).toList();

  if (ready.isEmpty) {
    final goCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No ready voices'),
        content: const Text(
          'Record a family voice first, then you can hear stories read in it.',
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
    if (goCreate == true && context.mounted) context.push('/voices/consent');
    return;
  }

  final voice = ready.length == 1 ? ready.first : await _pickVoice(context, ready);
  if (voice == null) return;

  try {
    final url = await ref
        .read(storyRepositoryProvider)
        .synthesize(story: story, voiceId: voice.id);
    if (context.mounted) {
      context.push('/player', extra: PlayerArgs(url: url, title: title));
    }
  } catch (error) {
    if (!context.mounted) return;
    // An unverified email surfaces the verify sheet, a free-tier limit the
    // paywall — either way, not a bare error.
    if (await showVerifyEmailIfNeeded(context, error)) return;
    if (!context.mounted) return;
    if (await showPaywallIfQuota(context, error)) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play the story: ${friendlyError(error)}')),
      );
    }
  }
}

Future<VoiceProfile?> _pickVoice(BuildContext context, List<VoiceProfile> ready) {
  return showModalBottomSheet<VoiceProfile>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Whose voice should tell it?'),
          ),
          for (final v in ready)
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(v.name),
              onTap: () => Navigator.pop(context, v),
            ),
        ],
      ),
    ),
  );
}
