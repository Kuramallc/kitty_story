import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../common/widgets/async_value_widget.dart';
import '../../../common/widgets/parental_gate.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../data/voice_repository.dart';
import '../domain/voice_profile.dart';
import '../../../common/widgets/page_width.dart';

/// Lists the family's cloned voices with live status, lets the user hear a
/// test line in any ready voice, add new voices, and delete them.
class VoicesScreen extends ConsumerStatefulWidget {
  const VoicesScreen({super.key});

  @override
  ConsumerState<VoicesScreen> createState() => _VoicesScreenState();
}

class _VoicesScreenState extends ConsumerState<VoicesScreen> {
  final AudioPlayer _player = AudioPlayer();

  /// Voice id currently synthesizing or playing its test line.
  String? _busyVoiceId;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playTestLine(VoiceProfile voice) async {
    if (_busyVoiceId != null) {
      await _player.stop();
      final wasThisVoice = _busyVoiceId == voice.id;
      setState(() => _busyVoiceId = null);
      if (wasThisVoice) return; // Tap on the playing voice = stop.
    }
    setState(() => _busyVoiceId = voice.id);
    try {
      final url = await ref
          .read(voiceRepositoryProvider)
          .synthesizeTestLine(voice.id);
      await _player.setUrl(url);
      await _player.play();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play the test line: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyVoiceId = null);
    }
  }

  Future<void> _confirmDelete(VoiceProfile voice) async {
    // A grown-up check before a destructive, data-removing action.
    if (!await showParentalGate(context)) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${voice.name}"?'),
        content: const Text(
          'This permanently removes the recording, the AI voice, and any '
          'story audio made with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(voiceRepositoryProvider).deleteVoice(voice.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    }
  }

  Future<void> _addVoice() async {
    // Free tier caps the number of voices — show the paywall instead of
    // recording another.
    final entitled = ref.read(entitlementActiveProvider).value ?? false;
    final count = ref.read(voicesStreamProvider).value?.length ?? 0;
    if (!entitled && count >= kFreeMaxVoices) {
      await showPaywall(
        context,
        reason:
            'The free plan includes $kFreeMaxVoices '
            '${kFreeMaxVoices == 1 ? 'voice' : 'voices'}.',
      );
      return;
    }
    // Parental gate before recording a voice.
    if (!await showParentalGate(context)) return;
    if (mounted) context.push('/voices/consent');
  }

  @override
  Widget build(BuildContext context) {
    final voices = ref.watch(voicesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Family voices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVoice,
        icon: const Icon(Icons.add),
        label: const Text('Add a voice'),
      ),
      body: SafeArea(
        child: PageWidth(
          child: AsyncValueWidget(
            value: voices,
            data: (list) => list.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _VoiceCard(
                      voice: list[index],
                      busy: _busyVoiceId == list[index].id,
                      onPlay: () => _playTestLine(list[index]),
                      onDelete: () => _confirmDelete(list[index]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.busy,
    required this.onPlay,
    required this.onDelete,
  });

  final VoiceProfile voice;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            voice.name.isEmpty ? '?' : voice.name[0].toUpperCase(),
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(voice.name, style: theme.textTheme.titleMedium),
        subtitle: _StatusChip(voice: voice),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (voice.isReady)
              busy
                  ? const SizedBox(
                      width: 40,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.play_circle_outline),
                      tooltip: 'Hear a test line',
                      onPressed: onPlay,
                    ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete voice',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.voice});

  final VoiceProfile voice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (voice.status) {
      VoiceStatus.pending ||
      VoiceStatus.processing => ('Creating…', scheme.tertiary),
      VoiceStatus.ready => ('Ready', scheme.primary),
      VoiceStatus.failed => ('Failed — try re-recording', scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.record_voice_over_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No voices yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Record Mom, Dad, or Grandma reading a short script, and '
              'Kitty Stories will tell bedtime stories in their voice.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
