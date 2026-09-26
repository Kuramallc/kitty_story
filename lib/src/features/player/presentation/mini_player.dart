import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_router.dart';
import '../application/audio_providers.dart';
import '../audio/audio_handler.dart';
import 'player_screen.dart';

/// A slim "now playing" bar shown above every screen while a story is playing.
///
/// Narration deliberately keeps going when you leave the player — you might
/// browse for the next story while this one finishes. But until now there was
/// no way back: `/player` is only reachable by pushing from a story, so once
/// popped, the only way to stop playback was the lock screen or the Android
/// notification shade. That is a poor ask of someone holding a sleeping child.
///
/// Tapping the bar reopens the full player; the buttons pause and stop in
/// place. It hides itself on the player screen, where it would be redundant.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  @override
  void initState() {
    super.initState();
    playerScreensOpen.addListener(_onPlayerScreensChanged);
  }

  @override
  void dispose() {
    playerScreensOpen.removeListener(_onPlayerScreensChanged);
    super.dispose();
  }

  void _onPlayerScreensChanged() {
    // PlayerScreen bumps the count from initState/dispose, i.e. while a frame
    // is being built. Marking this widget dirty right then is illegal — it
    // lives on a different branch of the tree, mounted from MaterialApp's
    // builder rather than under the Navigator — and the rebuild is dropped,
    // with notifyListeners swallowing the error. Repaint next frame instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerOrNullProvider);
    if (handler == null) return const SizedBox.shrink();

    // The router itself, not context.push: this widget is mounted from
    // MaterialApp.router's builder, which sits above GoRouter's inherited
    // widget, so there is no GoRouter in this context to read.
    final router = ref.watch(appRouterProvider);

    // Redundant while the full player is up.
    if (playerScreensOpen.value > 0) return const SizedBox.shrink();
    return _nowPlaying(handler, router);
  }

  Widget _nowPlaying(StoryAudioHandler handler, GoRouter router) {
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, itemSnap) {
        final item = itemSnap.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnap) {
            final state = stateSnap.data;
            // idle means stopped, completed means the story finished — in
            // neither case is there anything to come back to.
            const gone = {
              AudioProcessingState.idle,
              AudioProcessingState.completed,
            };
            if (state == null || gone.contains(state.processingState)) {
              return const SizedBox.shrink();
            }
            return _Bar(
              title: item.title,
              playing: state.playing,
              onPlayPause: () =>
                  state.playing ? handler.pause() : handler.play(),
              onStop: handler.stop,
              onOpen: () => router.push(
                '/player',
                extra: PlayerArgs(url: item.id, title: item.title),
              ),
            );
          },
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.playing,
    required this.onPlayPause,
    required this.onStop,
    required this.onOpen,
  });

  final String title;
  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onOpen,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.nightlight_round,
                    size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: playing ? 'Pause' : 'Play',
                  child: IconButton(
                    onPressed: onPlayPause,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Stop',
                  child: IconButton(
                    onPressed: onStop,
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
