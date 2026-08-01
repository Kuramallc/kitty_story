import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/audio_providers.dart';
import '../audio/audio_handler.dart';

/// Navigation payload for the player.
class PlayerArgs {
  const PlayerArgs({required this.url, required this.title});
  final String url;
  final String title;
}

const _sleepOptions = <int>[5, 10, 15, 30];

/// The bedtime player: large controls, a scrubber, and a sleep timer.
/// Background + lock-screen playback come from the audio_service handler.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlayerArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final handler = ref.read(audioHandlerProvider);
      await handler.loadStory(url: widget.args.url, title: widget.args.title);
      await handler.play();
    });
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Now playing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.nightlight_round, size: 120, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                widget.args.title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _ScrubBar(handler: handler),
              const SizedBox(height: 8),
              _Controls(handler: handler),
              const SizedBox(height: 16),
              _SleepTimer(handler: handler, onPick: () => _pickSleep(handler)),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSleep(StoryAudioHandler handler) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Pause after…')),
            for (final m in _sleepOptions)
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text('$m minutes'),
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (minutes != null) handler.setSleepTimer(Duration(minutes: minutes));
  }
}

class _ScrubBar extends StatelessWidget {
  const _ScrubBar({required this.handler});

  final StoryAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: handler.durationStream,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: handler.positionStream,
          builder: (context, posSnap) {
            final maxMs = duration.inMilliseconds.toDouble();
            final sliderMax = maxMs <= 0 ? 1.0 : maxMs;
            final position = posSnap.data ?? Duration.zero;
            final posMs = position.inMilliseconds.toDouble().clamp(0.0, sliderMax);
            return Column(
              children: [
                Slider(
                  value: posMs,
                  max: sliderMax,
                  onChanged: (v) => handler.seek(Duration(milliseconds: v.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_PlayerScreenState._fmt(position)),
                      Text(_PlayerScreenState._fmt(duration)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.handler});

  final StoryAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.replay_10),
          tooltip: 'Back 15 seconds',
          onPressed: handler.rewind,
        ),
        const SizedBox(width: 16),
        StreamBuilder<bool>(
          stream: handler.playingStream,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            return FilledButton(
              onPressed: () => playing ? handler.pause() : handler.play(),
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 40),
            );
          },
        ),
        const SizedBox(width: 16),
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.forward_10),
          tooltip: 'Forward 15 seconds',
          onPressed: handler.fastForward,
        ),
      ],
    );
  }
}

class _SleepTimer extends StatelessWidget {
  const _SleepTimer({required this.handler, required this.onPick});

  final StoryAudioHandler handler;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: handler.sleepRemaining,
      builder: (context, remaining, _) {
        if (remaining != null) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bedtime, size: 18),
              const SizedBox(width: 8),
              Text('Sleeping in ${_PlayerScreenState._fmt(remaining)}'),
              TextButton(
                onPressed: () => handler.setSleepTimer(null),
                child: const Text('Cancel'),
              ),
            ],
          );
        }
        return OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.bedtime_outlined),
          label: const Text('Sleep timer'),
        );
      },
    );
  }
}
