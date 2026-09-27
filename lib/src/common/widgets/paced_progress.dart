import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// A progress bar for a single long call whose real progress can't be observed.
///
/// `generateStory` is one request to one model: there are no stages to report,
/// so this bar is *paced* rather than measured. Two rules keep that honest
/// enough to be useful:
///
/// * It eases toward [_ceiling] and never arrives on its own. A bar that sits
///   at 100% while the caller is still waiting is worse than no bar at all —
///   it reads as a hang. Only [done] takes it to full.
/// * It advances in uneven steps. A perfectly even crawl reads as a frozen
///   animation; slightly irregular motion reads as work happening.
///
/// Nothing here is wired to backend events, and [messages] are pacing copy, not
/// reported stages — don't read them as a description of what the server is up
/// to.
class PacedProgress extends StatefulWidget {
  const PacedProgress({
    super.key,
    required this.done,
    this.duration = const Duration(seconds: 10),
    this.messages = const <String>[],
  });

  /// Flip to true when the real work finishes: the bar runs out to 100%.
  final bool done;

  /// Roughly how long the bar takes to crawl most of the way to [_ceiling].
  /// Overrunning is expected and handled — the bar just keeps easing.
  final Duration duration;

  /// Rotating copy shown under the bar, cycled while waiting.
  final List<String> messages;

  @override
  State<PacedProgress> createState() => _PacedProgressState();
}

/// Where the paced crawl tops out. The remaining sliver belongs to [done].
const double _ceiling = 0.92;
const Duration _tick = Duration(milliseconds: 220);
const Duration _messageEvery = Duration(milliseconds: 2600);

class _PacedProgressState extends State<PacedProgress> {
  final _random = Random();
  Timer? _timer;
  double _value = 0;
  int _elapsedTicks = 0;

  /// Fraction of the remaining gap to close per tick, solved so the bar is
  /// ~95% of the way to the ceiling after [PacedProgress.duration].
  late final double _rate = () {
    final ticks = widget.duration.inMilliseconds / _tick.inMilliseconds;
    return ticks <= 0 ? 1.0 : 1 - pow(0.05, 1 / ticks).toDouble();
  }();

  @override
  void initState() {
    super.initState();
    if (!widget.done) _start();
  }

  @override
  void didUpdateWidget(PacedProgress old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done) {
      _timer?.cancel();
      setState(() => _value = 1);
    } else if (!widget.done && old.done) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      setState(() {
        _elapsedTicks++;
        // Uneven steps: half to one-and-a-half of the nominal rate. Averages
        // out to the solved pace, but no two steps look alike.
        final jitter = 0.5 + _random.nextDouble();
        _value += (_ceiling - _value) * _rate * jitter;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? get _message {
    if (widget.messages.isEmpty) return null;
    final shown = _elapsedTicks * _tick.inMilliseconds;
    final index = shown ~/ _messageEvery.inMilliseconds;
    return widget.messages[index % widget.messages.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _value),
          // Slightly longer than a tick so each step glides into the next
          // instead of snapping.
          duration: _tick * 1.2,
          curve: Curves.easeOut,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          // The bar is the progress cue; the copy is only reassurance, so it
          // stays out of the live region rather than interrupting a screen
          // reader every few seconds.
          ExcludeSemantics(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              // Sequential, not a cross-fade: AnimatedSwitcher stacks its
              // children, and two centred lines of different lengths fading
              // through each other render as one garbled line. Pushing both
              // curves into their own half means the old line is gone before
              // the new one appears.
              switchOutCurve: const Interval(0.5, 1.0),
              switchInCurve: const Interval(0.5, 1.0),
              child: Text(
                message,
                key: ValueKey(message),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
