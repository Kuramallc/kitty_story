import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/parental_gate.dart';
import '../../auth/presentation/verify_email_sheet.dart';
import '../../player/presentation/player_screen.dart';
import '../../voices/data/voice_repository.dart';
import '../../voices/domain/voice_profile.dart';
import '../data/story_repository.dart';
import '../domain/story.dart';

/// Reads a story and lets the user hear it narrated in a chosen cloned voice.
/// Synthesizing hands off to the full bedtime player ([PlayerScreen]).
class StoryDetailScreen extends ConsumerStatefulWidget {
  const StoryDetailScreen({super.key, required this.story});

  final Story story;

  @override
  ConsumerState<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends ConsumerState<StoryDetailScreen> {
  bool _busy = false;

  Future<void> _tellInVoice() async {
    final List<VoiceProfile> voices;
    try {
      voices = await ref.read(voiceRepositoryProvider).fetchVoices();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load your voices: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
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
      if (goCreate == true && mounted) context.push('/voices/consent');
      return;
    }

    final voice = ready.length == 1 ? ready.first : await _pickVoice(ready);
    if (voice == null) return;

    setState(() => _busy = true);
    try {
      final url = await ref
          .read(storyRepositoryProvider)
          .synthesize(story: widget.story, voiceId: voice.id);
      if (mounted) {
        context.push('/player',
            extra: PlayerArgs(url: url, title: widget.story.title));
      }
    } catch (error) {
      if (!mounted) return;
      if (await showVerifyEmailIfNeeded(context, error)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play the story: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<VoiceProfile?> _pickVoice(List<VoiceProfile> ready) {
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

  /// Publishing makes the story visible to other families' children, so it's
  /// gated behind a grown-up check.
  Future<void> _share(Story story) async {
    if (!await showParentalGate(context)) return;
    if (mounted) context.push('/stories/publish', extra: story);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = widget.story;
    return Scaffold(
      appBar: AppBar(
        title: Text(story.title),
        actions: [
          if (story.source == StorySource.generated)
            TextButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
              onPressed: () => _share(story),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                children: [
                  Text(story.title, style: theme.textTheme.headlineSmall),
                  if (story.ageRange != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'For ${story.ageRange}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(story.text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
                ],
              ),
            ),
            Material(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _tellInVoice,
                    icon: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_busy ? 'Preparing…' : 'Tell it in a voice'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
