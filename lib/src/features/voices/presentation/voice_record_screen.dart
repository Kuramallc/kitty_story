import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../auth/presentation/verify_email_sheet.dart';
import '../application/recording_controller.dart';

/// What the caregiver reads aloud. Starts with a spoken permission statement
/// (doubles as recorded consent inside the sample itself), then warm,
/// varied text — different sentence lengths and tones improve clone quality.
const String kRecordingScript = '''
I give my permission for Kitty Stories to make a copy of my voice, so it can read bedtime stories to my family.

Once upon a time, in a cozy little house at the edge of a quiet town, there lived a small grey kitten named Luna. Luna loved three things: warm blankets, gentle rain on the window, and stories before bed.

"Are you sleepy yet?" she would ask the moon. The moon never answered, but it always smiled.

Some nights were loud, and some nights were still. On the still nights, Luna listened to the crickets sing — one, two, three — until her eyes grew heavy.

Tonight, my little one, I want you to close your eyes. Take a slow, deep breath. Imagine the softest cloud, floating just for you. I am right here. I love you to the moon and back, and I will see you in the morning. Sweet dreams. Goodnight.''';

class VoiceRecordScreen extends ConsumerStatefulWidget {
  const VoiceRecordScreen({super.key, required this.voiceName});

  final String voiceName;

  @override
  ConsumerState<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

class _VoiceRecordScreenState extends ConsumerState<VoiceRecordScreen> {
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _previewing = false;

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(String path) async {
    if (_previewing) {
      await _previewPlayer.stop();
      setState(() => _previewing = false);
      return;
    }
    setState(() => _previewing = true);
    try {
      await _previewPlayer.setFilePath(path);
      await _previewPlayer.play();
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _submit() async {
    final ok = await ref
        .read(recordingControllerProvider.notifier)
        .submit(widget.voiceName);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Creating "${widget.voiceName}" — this takes a minute.')),
      );
      // Pop back through consent + record (rather than context.go, which
      // would replace the whole stack) so the Voices screen we land on is
      // the one already pushed from Home — keeping its back button intact.
      context.pop();
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);
    final theme = Theme.of(context);

    ref.listen(recordingControllerProvider, (prev, next) {
      final message = next.errorMessage;
      if (message == null || message == prev?.errorMessage) return;
      // A rejection the user can actually act on gets the verify sheet; only
      // genuinely unexpected failures show their exception text.
      final cause = next.errorCause;
      if (cause != null && isEmailNotVerified(cause)) {
        showVerifyEmail(context);
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });

    final minutes = state.elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (state.elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: Text('Record ${widget.voiceName}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Read this aloud in your natural storytelling voice. '
                'Aim for 1–2 minutes.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      kRecordingScript,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Level meter + timer.
              Row(
                children: [
                  Icon(
                    state.phase == RecordingPhase.recording
                        ? Icons.mic
                        : Icons.mic_none,
                    color: state.phase == RecordingPhase.recording
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: state.phase == RecordingPhase.recording
                            ? state.level.clamp(0.05, 1.0)
                            : 0,
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$minutes:$seconds', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              ..._buildActions(state, controller, theme),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    RecordingState state,
    RecordingController controller,
    ThemeData theme,
  ) {
    switch (state.phase) {
      case RecordingPhase.idle:
        return [
          FilledButton.icon(
            onPressed: controller.start,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Start recording'),
          ),
        ];
      case RecordingPhase.recording:
        return [
          FilledButton.icon(
            onPressed: controller.stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ];
      case RecordingPhase.recorded:
        return [
          if (!state.canSubmit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'That was a bit short — at least 15 seconds is needed, '
                'and 1–2 minutes sounds best.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.filePath == null
                      ? null
                      : () => _togglePreview(state.filePath!),
                  icon: Icon(_previewing ? Icons.stop : Icons.play_arrow),
                  label: Text(_previewing ? 'Stop' : 'Listen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.discard,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-record'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.canSubmit ? _submit : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Create this voice'),
          ),
        ];
      case RecordingPhase.submitting:
        return [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Uploading and creating the voice…',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ];
    }
  }
}
