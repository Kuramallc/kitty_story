import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../data/voice_repository.dart';

/// Hard cap per ElevenLabs guidance: >3 min adds nothing to clone quality.
const Duration kMaxRecording = Duration(minutes: 3);

/// Below this the clone quality drops off badly.
const Duration kMinRecording = Duration(seconds: 15);

enum RecordingPhase { idle, recording, recorded, submitting }

class RecordingState {
  const RecordingState({
    this.phase = RecordingPhase.idle,
    this.elapsed = Duration.zero,
    this.level = 0,
    this.filePath,
    this.errorMessage,
  });

  final RecordingPhase phase;
  final Duration elapsed;

  /// Mic input level normalized to 0..1 for the meter.
  final double level;
  final String? filePath;
  final String? errorMessage;

  bool get canSubmit =>
      phase == RecordingPhase.recorded &&
      filePath != null &&
      elapsed >= kMinRecording;

  RecordingState copyWith({
    RecordingPhase? phase,
    Duration? elapsed,
    double? level,
    String? filePath,
    String? errorMessage,
  }) {
    return RecordingState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      level: level ?? this.level,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage,
    );
  }
}

/// Drives the guided voice-sample recording flow (mic → m4a file → upload+clone).
class RecordingController extends Notifier<RecordingState> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSub;

  @override
  RecordingState build() {
    ref.onDispose(() async {
      _ticker?.cancel();
      await _amplitudeSub?.cancel();
      await _recorder.dispose();
    });
    return const RecordingState();
  }

  Future<void> start() async {
    if (state.phase == RecordingPhase.recording) return;
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(
        errorMessage: 'Microphone access is needed to record a voice. '
            'Enable it in Settings and try again.',
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_sample_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: path,
    );

    state = const RecordingState(phase: RecordingPhase.recording);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = state.elapsed + const Duration(seconds: 1);
      if (elapsed >= kMaxRecording) {
        stop();
      } else {
        state = state.copyWith(elapsed: elapsed);
      }
    });
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      // dBFS roughly -45 (silence) .. 0 (max) → 0..1.
      final normalized = ((amp.current.clamp(-45.0, 0.0)) + 45.0) / 45.0;
      state = state.copyWith(level: normalized);
    });
  }

  Future<void> stop() async {
    if (state.phase != RecordingPhase.recording) return;
    _ticker?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final path = await _recorder.stop();
    state = state.copyWith(
      phase: path == null ? RecordingPhase.idle : RecordingPhase.recorded,
      filePath: path,
      level: 0,
    );
  }

  Future<void> discard() async {
    _ticker?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (state.phase == RecordingPhase.recording) await _recorder.cancel();
    final path = state.filePath;
    if (path != null) await File(path).delete().catchError((_) => File(path));
    state = const RecordingState();
  }

  /// Uploads the sample and kicks off cloning. Returns true on success.
  Future<bool> submit(String name) async {
    final path = state.filePath;
    if (path == null || !state.canSubmit) return false;
    state = state.copyWith(phase: RecordingPhase.submitting);
    try {
      await ref
          .read(voiceRepositoryProvider)
          .createVoiceAndClone(name: name, sample: File(path));
      return true;
    } catch (error) {
      state = state.copyWith(
        phase: RecordingPhase.recorded,
        errorMessage: 'Could not create the voice: $error',
      );
      return false;
    }
  }
}

final recordingControllerProvider =
    NotifierProvider.autoDispose<RecordingController, RecordingState>(
        RecordingController.new);
